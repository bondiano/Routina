#!/usr/bin/env luajit
-- import-bis.lua -- generate Routina's BiS catalog from the vendored
-- Warkdev/BestInSlotTBCClassic data (GPL-2.0). Run via `task import-bis`.
--
-- Pipeline: dofile the vendored Lua data tables, join
--   BIS_LINKS {ClassId,SpecId,ItemId,Priority} (bis_data.lua)
--   x BIS_ITEMS[id] {Phase,Slot,Raid,WorldBoss,ReputationLevel} (items.lua)
--   x class/spec/slot maps (below)
--   x BIS_ITEM_NAMES[id] (item-names.lua, MIT nexus-devs)
-- then emit one pure Fennel data module per class to src/domain/bis/<class>.fnl,
-- each entry conforming to schemas.BisItem. Deterministic: sorted output.
--
-- The class/spec maps are transcribed from the same addon's modules/manager.lua
-- (BIS_dataSpecs.SPEC / .VALUE); that file pulls WoW API globals so it cannot be
-- dofile-d here. SpecId is the 1-based index into a class's SPEC list.

local SRC = "vendor/bis-source"
local OUT = "src/domain/bis"

-- Import EVERY source rank (ROADMAP Phase 4b decision). Priority 1 is the
-- canonical best-in-slot per (spec, slot); deeper Priorities are the ranked
-- alternatives and the pre-raid / catch-up long tail the BiS tab now surfaces.
-- The source's Priority runs to ~30; full import is ~5100 entries (vs ~820 at
-- Priority 1-2), biggest spec file ~250 entries -- generated data, exempt from
-- the 300-line guideline. The downstream UI / route scoring cap the tail
-- (OQ-9), the catalog itself stays complete. 99 = effectively uncapped.
local MAX_PRIORITY = 99

-- ClassId -> Routina class keyword (matches schemas.BisItem :class enum).
local CLASS = {
  [1] = "warrior", [2] = "paladin", [3] = "hunter", [4] = "rogue",
  [5] = "priest", [7] = "shaman", [8] = "mage", [9] = "warlock", [11] = "druid",
}
-- Stable class emission order.
local CLASS_ORDER = {"warrior", "paladin", "hunter", "rogue", "priest",
                     "shaman", "mage", "warlock", "druid"}

-- ClassId -> { [SpecId] = spec-keyword }. From manager.lua BIS_dataSpecs.SPEC,
-- VALUE = {1,2,3,...} so SpecId is the list index. Source taxonomy is preserved
-- verbatim, including its quirks (documented in vendor/bis-source/README.md):
--   priest spec 1 ("Holy") is the merged Holy+Discipline set (PriestHybrid);
--   rogue has a single "Any" spec; warrior/druid keep the source's protection
--   and feral splits.
local SPEC = {
  [1]  = {"arms", "fury", "protection-threat", "protection-mitigation"},
  [2]  = {"holy", "protection", "retribution"},
  [3]  = {"beast-mastery", "marksmanship", "survival"},
  [4]  = {"any"},
  [5]  = {"holy", "shadow"},
  [7]  = {"restoration", "enhancement", "elemental"},
  [8]  = {"arcane", "fire", "frost"},
  [9]  = {"affliction", "demonology", "destruction"},
  [11] = {"feral-tank-mitigation", "feral-tank-threat", "feral-dps",
          "restoration", "balance"},
}

-- items.lua Slot int -> Routina slot keyword. Rings (11) and trinkets (13) are
-- "base" paired slots: the source files every ring as Slot 11 / trinket as Slot
-- 13, so the ranked pool is split across ring1/ring2 (trinket1/trinket2) below.
-- Slots not present (0 = no/relic-less, 4 = shirt, 19 = tabard, 23/24 = bag/ammo)
-- have no BiS-gear slot in schemas.BisItem and are skipped + counted.
local SLOT = {
  [1] = "head", [2] = "neck", [3] = "shoulder", [5] = "chest", [6] = "waist",
  [7] = "legs", [8] = "feet", [9] = "wrist", [10] = "hands", [15] = "back",
  [16] = "main-hand", [17] = "off-hand", [18] = "ranged",
}
local PAIRED = {[11] = {"ring1", "ring2"}, [13] = {"trinket1", "trinket2"}}

-- ---- load vendored data (sets globals) ------------------------------------
dofile(SRC .. "/class.lua")          -- CLASS_IDX, CLASS_ID
dofile(SRC .. "/inventoryslot.lua")  -- INVSLOT_IDX, ...
dofile(SRC .. "/items.lua")          -- BIS_ITEMS
dofile(SRC .. "/bis_data.lua")       -- BIS_LINKS
dofile(SRC .. "/item-names.lua")     -- BIS_ITEM_NAMES

-- ---- helpers ---------------------------------------------------------------
-- Best-effort :instance from the source's coarse flags. The source carries no
-- per-item boss or drop-rate (that lands with the Phase 2 drop-table), so this
-- is the only provenance available. Today's distribution: ~665 :raid,
-- ~151 :unknown, ~4 :world-boss, 0 :reputation. The :reputation branch is
-- currently unreachable for this dataset (rep gear is not flagged via
-- ReputationLevel here) but kept as a defensive fallback. :unknown is a genuine
-- catch-all (crafted / dungeon / badge / PvP / quest gear), NOT "some raid".
local function instance_of(meta)
  if meta.Raid then return "raid" end
  if meta.WorldBoss then return "world-boss" end
  if (meta.ReputationLevel or 0) > 0 then return "reputation" end
  return "unknown"
end

-- :kind derivation (ROADMAP Phase 4b / OQ-8). The source has NO explicit
-- pre-raid list (items.lua Phase is 1-5, never 0), so kind is synthesised from
-- provenance flags: a raid drop, world-boss drop, or tier-set token purchase is
-- the endgame target (:bis); everything else at the slot's entry phase
-- (dungeon / heroic / crafted / reputation / quest / vendor / PvP / BoE) is the
-- catch-up gear worn toward it (:pre-raid). Refining the :pre-raid bucket via
-- item-sources.lua `category` is possible later (OQ-8) but not needed for the
-- bis/pre-raid split itself.
local function kind_of(meta)
  if meta.Raid or meta.WorldBoss or (meta.TokenId or 0) > 0 then
    return "bis"
  end
  return "pre-raid"
end

local function item_name(id)
  return BIS_ITEM_NAMES[id] or string.format("Item #%d", id)
end

-- Fennel literal emitters.
local function kw(s) return ":" .. s end
local function str(s) return string.format("%q", s) end

-- ---- join ------------------------------------------------------------------
local skipped = {no_meta = 0, no_slot = 0, no_spec = 0}
local missing_names = 0

-- SpecIds the source carries that have no PvE-spec entry in SPEC above, and are
-- deliberately omitted: the MAGIC_RESISTANCE / PvP resist variant sets (see
-- manager.lua BIS_dataSpecs.MAGIC_RESISTANCE). A dropped (ClassId, SpecId) NOT
-- in this allowlist means the source added something real -> warn loudly rather
-- than drop it silently.
local OMITTED_SPECS = {
  [1] = {[5] = true, [6] = true, [7] = true},  -- warrior resist variants
  [2] = {[4] = true, [5] = true},              -- paladin resist variants
  [9] = {[4] = true},                          -- warlock resist variant
  [11] = {[6] = true, [7] = true},             -- druid resist variants
}
-- buckets[class][spec] = list of {phase, slotbase, paired(bool), id, name,
--   priority, instance}; paired entries get their final slot assigned after sort.
local buckets = {}
local seen = {}  -- dedup key class|spec|phase|slotbase|id -> true

for _, link in ipairs(BIS_LINKS) do
  local class = CLASS[link.ClassId]
  local specs = SPEC[link.ClassId]
  local spec = specs and specs[link.SpecId]
  local meta = BIS_ITEMS[link.ItemId]
  if class and (link.Priority or 99) <= MAX_PRIORITY then
    if not spec then
      -- Known resist/PvP variant SpecId -> drop quietly; anything else is new.
      skipped.no_spec = skipped.no_spec + 1
      if not (OMITTED_SPECS[link.ClassId] and OMITTED_SPECS[link.ClassId][link.SpecId]) then
        print(string.format(
          "  WARNING: dropped unmapped spec ClassId=%d SpecId=%d (item %d) -- "
          .. "source may have added a real spec; update SPEC in import-bis.lua",
          link.ClassId, link.SpecId, link.ItemId))
      end
    elseif not meta then
      skipped.no_meta = skipped.no_meta + 1
    elseif not (SLOT[meta.Slot] or PAIRED[meta.Slot]) then
      skipped.no_slot = skipped.no_slot + 1
    else
      local phase = math.floor(meta.Phase or 1)
      local slotbase = SLOT[meta.Slot] or ("paired" .. meta.Slot)
      local key = table.concat({class, spec, phase, slotbase, link.ItemId}, "|")
      if not seen[key] then
        seen[key] = true
        buckets[class] = buckets[class] or {}
        buckets[class][spec] = buckets[class][spec] or {}
        local nm = BIS_ITEM_NAMES[link.ItemId]
        if not nm then missing_names = missing_names + 1 end
        table.insert(buckets[class][spec], {
          phase = phase, paired = PAIRED[meta.Slot], slot = SLOT[meta.Slot],
          slotbase = meta.Slot, id = link.ItemId, name = item_name(link.ItemId),
          priority = link.Priority or 99, instance = instance_of(meta),
          kind = kind_of(meta),
        })
      end
    end
  end
end

-- ---- assign paired slots (ring1/ring2, trinket1/trinket2) ------------------
-- Within (spec, phase, paired-base), sort by (priority, id) and alternate the
-- ranked pool across the two slots: rank 1 -> slot A, rank 2 -> slot B, ...
local function assign_paired(entries)
  local pools = {}  -- (spec|phase|base) -> list
  for _, e in ipairs(entries) do
    if e.paired then
      local k = table.concat({e.phase, e.slotbase}, "|")
      pools[k] = pools[k] or {}
      table.insert(pools[k], e)
    end
  end
  for _, pool in pairs(pools) do
    table.sort(pool, function(a, b)
      if a.priority ~= b.priority then return a.priority < b.priority end
      return a.id < b.id
    end)
    for i, e in ipairs(pool) do
      e.slot = e.paired[(i % 2 == 1) and 1 or 2]
    end
  end
end

-- ---- emit ------------------------------------------------------------------
local function entry_fennel(e)
  return string.format(
    "   {:class %s :spec %s :phase %d :kind %s :rank %d :slot %s\n"
    .. "    :item {:id %d :name %s}\n"
    .. "    :sources [{:instance %s}]}",
    kw(e.class), kw(e.spec), e.phase, kw(e.kind), e.priority, kw(e.slot),
    e.id, str(e.name), kw(e.instance))
end

-- One pure data module per (class, spec) -> src/domain/bis/<class>-<spec>.fnl,
-- each registering into Routina.bis-by-spec keyed by "class-spec" (overwrite, so
-- re-require is idempotent). Per-spec keeps every file well under the 300-line
-- source guideline. bis-catalog.fnl flattens the accumulator.
local function write_spec(class, spec, entries)
  for _, e in ipairs(entries) do e.class = class; e.spec = spec end
  assign_paired(entries)
  table.sort(entries, function(a, b)
    if a.phase ~= b.phase then return a.phase < b.phase end
    if a.slot ~= b.slot then return a.slot < b.slot end
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.id < b.id
  end)
  local lines = {}
  for _, e in ipairs(entries) do lines[#lines + 1] = entry_fennel(e) end
  local name = class .. "-" .. spec
  local body = string.format([[
;; src/domain/bis/%s.fnl -- GENERATED by scripts/import-bis.lua. DO NOT EDIT.
;; Source: Warkdev/BestInSlotTBCClassic (GPL-2.0); item names: nexus-devs (MIT).
;; See vendor/bis-source/README.md. Regenerate: task vendor-bis-source && task import-bis.
;;
;; Pure data: schemas.BisItem entries for %s %s, registered into the shared
;; accumulator that src/domain/bis-catalog.fnl flattens. No WoW API.

(local Routina (or _G.Routina {}))
(set _G.Routina Routina)

(local by-spec (or Routina.bis-by-spec {}))
(set Routina.bis-by-spec by-spec)

(local entries
       [%s])

(tset by-spec %s entries)

entries
]], name, class, spec, table.concat(lines, "\n"), kw(name))
  local f = assert(io.open(OUT .. "/" .. name .. ".fnl", "w"))
  f:write(body)
  f:close()
  return #entries
end

-- manifest.fnl: the ordered list of (class-spec) module basenames, so
-- bis-catalog.fnl can require them outside addon scope (tests) and validate
-- coverage. Generated so it can never drift from the emitted files.
local function write_manifest(names)
  local kws = {}
  for _, n in ipairs(names) do kws[#kws + 1] = "  " .. kw(n) end
  local body = string.format([[
;; src/domain/bis/manifest.fnl -- GENERATED by scripts/import-bis.lua. DO NOT EDIT.
;; The ordered (class-spec) modules that make up the BiS catalog. bis-catalog.fnl
;; reads this to know which per-spec modules to aggregate.

(local Routina (or _G.Routina {}))
(set _G.Routina Routina)

(local manifest
       [%s])

(set Routina.bis-manifest manifest)

manifest
]], table.concat(kws, "\n"))
  local f = assert(io.open(OUT .. "/manifest.fnl", "w"))
  f:write(body)
  f:close()
end

os.execute("mkdir -p " .. OUT)
os.execute("rm -f " .. OUT .. "/*.fnl")
local total, names = 0, {}
print("=== BiS import ===")
for _, class in ipairs(CLASS_ORDER) do
  local specs = buckets[class] or {}
  local speclist = {}
  for spec in pairs(specs) do speclist[#speclist + 1] = spec end
  table.sort(speclist)
  for _, spec in ipairs(speclist) do
    total = total + write_spec(class, spec, specs[spec])
    names[#names + 1] = class .. "-" .. spec
  end
  print(string.format("  %-8s specs: %s", class, table.concat(speclist, ", ")))
end
write_manifest(names)

-- Emit the .toc load-order fragment (build paths) for the wiring step.
local toc = {}
for _, n in ipairs(names) do toc[#toc + 1] = "build\\domain\\bis\\" .. n .. ".lua" end
toc[#toc + 1] = "build\\domain\\bis\\manifest.lua"
local tf = assert(io.open(SRC .. "/toc-fragment.txt", "w"))
tf:write(table.concat(toc, "\n") .. "\n")
tf:close()

print(string.format("total=%d entries  %d spec-modules  skipped(no-spec)=%d skipped(no-meta)=%d skipped(no-slot)=%d missing-names=%d",
  total, #names, skipped.no_spec, skipped.no_meta, skipped.no_slot, missing_names))
print("toc fragment -> " .. SRC .. "/toc-fragment.txt")
