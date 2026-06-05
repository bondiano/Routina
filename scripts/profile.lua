-- scripts/profile.lua -- performance budget check (PRD M5 / ROADMAP Phase 5).
-- Asserts `route.plan-week` stays under 5 ms median over 100 fixture players.
-- Run via `task profile` (luajit, after `task build`).
--
-- Mirrors spec/helper.lua: JIT off (WoW ships PUC Lua 5.1, so the plain
-- interpreter is the closest match) and `src.*` resolved to the compiled
-- build/ output -- we measure the Lua that actually ships in-game.

if jit then
  jit.off()
  jit.flush()
end

local function build_lua_searcher(modname)
  local rel = modname:match("^src%.(.+)$")
  if not rel then return nil end
  local path = "./build/" .. rel:gsub("%.", "/") .. ".lua"
  local f = io.open(path, "r")
  if not f then
    return "\n\tno file '" .. path .. "' (run `task build`)"
  end
  f:close()
  return assert(loadfile(path))
end
table.insert(package.loaders, 1, build_lua_searcher)

local route = require("src.domain.route")
local activities = require("src.domain.activities")
local bis_catalog = require("src.domain.bis-catalog")

local BUDGET_MS = 5 -- PRD §7 M5: median < 5 ms on a mid-range laptop
local PLAYERS = 100
local REPS = 3 -- per-player timing = min of REPS runs (drops scheduler noise)

-- Deterministic LCG (mirrors spec/helpers/gen.fnl) so the fixture population
-- -- and therefore the measurement -- is reproducible run to run.
local lcg_state = 42
local function rng()
  lcg_state = (lcg_state * 1103515245 + 12345) % 2147483648
  return lcg_state / 2147483648
end

-- Grant every attunement / rep gate in the registry to all fixtures, so the
-- candidate activity set (and the measured work) is maximal.
local attunements, reputations = {}, {}
for _, adef in ipairs(activities.all()) do
  local req = adef.requirements or {}
  if req.attunement then attunements[req.attunement] = true end
  if req.rep then reputations[req.rep.faction] = "exalted" end
end

-- One fixture per (class, spec) pair, round-robin until PLAYERS is reached.
local classes = {
  "warrior", "paladin", "hunter", "rogue", "priest",
  "shaman", "mage", "warlock", "druid",
}
local class_specs = {}
for _, class in ipairs(classes) do
  for _, spec in ipairs(bis_catalog["specs-for-class"](class)) do
    table.insert(class_specs, { class = class, spec = spec })
  end
end

local function fixture(i)
  local cs = class_specs[(i - 1) % #class_specs + 1]
  -- Own a growing fraction of the spec's catalog across the population, so
  -- both the gearing-up and the endgame scoring paths are exercised.
  local own_p = (i - 1) / PLAYERS
  local owned = {}
  for _, entry in ipairs(bis_catalog["by-class-spec"](cs.class, cs.spec)) do
    if rng() < own_p then owned[entry.item.id] = true end
  end
  local ctx = {
    class = cs.class,
    spec = cs.spec,
    phase = 1,
    now = 0,
    ["owned-items"] = owned,
    lockouts = {},
  }
  -- Sprinkle the optional knobs over subsets of the population so the by-role
  -- competition, slot-weight and global-slider paths all get measured.
  if i % 3 == 0 then
    ctx.composition = { tank = 2, healer = 3, melee = 2, ranged = 1, caster = 2 }
  end
  if i % 4 == 0 then ctx.weights = { feet = 5, trinket = 3 } end
  if i % 5 == 0 then ctx["default-competitors"] = 4 end
  local player = {
    level = 70,
    attunements = attunements,
    reputations = reputations,
  }
  return player, ctx
end

-- Warmup: the catalog flatten and the competition item->roles index build
-- lazily on first use; they are load-time costs, not per-plan costs.
local warm_player, warm_ctx = fixture(1)
route["plan-week"](warm_player, warm_ctx)

local timings = {}
for i = 1, PLAYERS do
  local player, ctx = fixture(i)
  local best
  for _ = 1, REPS do
    local t0 = os.clock()
    route["plan-week"](player, ctx)
    local dt = (os.clock() - t0) * 1000
    if not best or dt < best then best = dt end
  end
  timings[i] = best
end

table.sort(timings)
local function percentile(p)
  return timings[math.max(1, math.min(PLAYERS, math.floor(p * PLAYERS + 0.5)))]
end
local median, p90, max_ms = percentile(0.5), percentile(0.9), timings[PLAYERS]

print(string.format(
  "route.plan-week over %d fixture players (%d class/spec pairs, luajit interpreter):",
  PLAYERS, #class_specs))
print(string.format(
  "  median %.2f ms | p90 %.2f ms | max %.2f ms  (budget: median < %d ms)",
  median, p90, max_ms, BUDGET_MS))

if median >= BUDGET_MS then
  print("FAIL -- median over budget")
  os.exit(1)
end
print("PASS")
