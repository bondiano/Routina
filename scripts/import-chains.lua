#!/usr/bin/env luajit
-- import-chains.lua -- generate src/domain/chains/data.fnl (chain-id -> ChainDef)
-- from vendor/chain-source/AttuneData.lua (the Attune addon by Cixi; ships no
-- license -- redistribution risk accepted by the owner 2026-06-05, see
-- CREDITS.md; the Routina aggregate is GPL-3.0). Run via `task import-chains`.
--
-- Pipeline:
--   - stub AttuneLang as an identity table, dofile the vendored data
--   - keep attunes with EXPAC == "The Burning Crusade" (phase-faithful)
--   - drop Spacer steps and steps outside the .toc interface window
--     (Attune encodes patch-dependent step variants via VALIDFROM/VALIDTO)
--   - parse FOLLOWS: "&" -> :all, "|" -> :any; the dataset has no mixed
--     expressions (asserted, so a future upstream change fails loudly)
--   - prune follows-ids that point at dropped steps
--   - emit one sorted pure-Fennel data module conforming to schemas.ChainDef
--
-- Attune data carries NO coordinates; ChainStep :coord stays nil until
-- Phase 9 supplies waypoint data from a separate source.

local SRC = "vendor/chain-source"
local OUT = "src/domain/chains"

-- The .toc interface number gates VALIDFROM/VALIDTO step variants.
local INTERFACE
do
  local f = assert(io.open("Routina.toc"))
  INTERFACE = tonumber(f:read("*a"):match("## Interface:%s*(%d+)"))
  f:close()
  assert(INTERFACE, "could not read ## Interface from Routina.toc")
end

-- The data file indexes AttuneLang for localized strings and assigns into a
-- pre-existing Attune_Data table; stub both so it loads standalone.
AttuneLang = setmetatable({}, {__index = function(_, k) return k end})
Attune_Data = {}
dofile(SRC .. "/AttuneData.lua")

local TBC = "The Burning Crusade"

local TYPE_KW = {
  Quest = "quest", Kill = "kill", Item = "item", ["Pick Up"] = "pickup",
  ["Turn In"] = "turnin", Level = "level", Rep = "rep",
  Interact = "interact", Click = "click", Attune = "attune", End = "end",
}
local QUESTISH = {quest = true, pickup = true, turnin = true}

local function slug(name)
  return (name:gsub("'", ""):lower():gsub("[^%w]+", "-")
              :gsub("^%-", ""):gsub("%-$", ""))
end

-- Faction variants of the same chain (Nightbane Horde/Alliance, ...) get a
-- faction-suffixed id; "Both" chains keep the bare slug.
local function chain_id(a)
  local id = slug(a.NAME)
  if a.FACTION and a.FACTION ~= "Both" then
    id = id .. "-" .. a.FACTION:lower()
  end
  return id
end

local function step_valid(s)
  if s.VALIDFROM and INTERFACE < s.VALIDFROM then return false end
  if s.VALIDTO and INTERFACE >= s.VALIDTO then return false end
  return true
end

local function parse_follows(raw)
  if not raw or raw == "" or raw == "0" then return {}, "all" end
  assert(not (raw:find("&", 1, true) and raw:find("|", 1, true)),
         "mixed &/| FOLLOWS expression not supported: " .. raw)
  local mode = raw:find("|", 1, true) and "any" or "all"
  local ids = {}
  for id in raw:gmatch("[^&|]+") do ids[#ids + 1] = id end
  return ids, mode
end

-- Gather TBC attunes (source order preserved for stable review diffs).
local chains, order = {}, {}
local counts = {steps = 0, spacers = 0, version_dropped = 0,
                duplicate_ids = 0, pruned_follows = 0}
for _, a in ipairs(Attune_Data.attunes) do
  if a.EXPAC == TBC then
    local cid = chain_id(a)
    assert(not chains[cid], "chain id collision: " .. cid)
    order[#order + 1] = cid
    chains[cid] = {def = a, steps = {}, seen = {}}
  end
end

local by_attune_id = {}
for cid, c in pairs(chains) do by_attune_id[c.def.ID] = cid end

for _, s in ipairs(Attune_Data.steps) do
  local cid = by_attune_id[s.ID_ATTUNE]
  if cid then
    local c = chains[cid]
    if s.TYPE == "Spacer" then
      counts.spacers = counts.spacers + 1
    elseif not step_valid(s) then
      counts.version_dropped = counts.version_dropped + 1
    elseif c.seen[s.ID] then
      counts.duplicate_ids = counts.duplicate_ids + 1
    else
      c.seen[s.ID] = true
      local kw = assert(TYPE_KW[s.TYPE], "unknown step TYPE: " .. tostring(s.TYPE))
      local follows, mode = parse_follows(s.FOLLOWS)
      local label = s.STEP
      if not label or label == "" then
        label = s.TYPE .. (s.LOCATION ~= "" and (" - " .. s.LOCATION) or "")
      end
      if s.COUNT then label = label .. " x" .. s.COUNT end
      local quest_id = QUESTISH[kw] and tonumber(s.ID_WOWHEAD) or nil
      if quest_id == 0 then quest_id = nil end
      counts.steps = counts.steps + 1
      c.steps[#c.steps + 1] = {
        id = s.ID, type = kw, label = label, quest_id = quest_id,
        stage = tonumber(s.STAGE), follows = follows, mode = mode,
      }
    end
  end
end

-- Prune follows-ids that point at dropped (Spacer / out-of-version) steps and
-- order steps by stage, then numeric id, for deterministic output.
for _, cid in ipairs(order) do
  local c = chains[cid]
  local present = {}
  for _, st in ipairs(c.steps) do present[st.id] = true end
  for _, st in ipairs(c.steps) do
    local kept = {}
    for _, fid in ipairs(st.follows) do
      if present[fid] then kept[#kept + 1] = fid
      else counts.pruned_follows = counts.pruned_follows + 1 end
    end
    st.follows = kept
  end
  table.sort(c.steps, function(x, y)
    if x.stage ~= y.stage then return (x.stage or 0) < (y.stage or 0) end
    return (tonumber(x.id) or 0) < (tonumber(y.id) or 0)
  end)
end

-- Emit.
local function step_fennel(st)
  local parts = {
    string.format(":id %q :type :%s :label %q", st.id, st.type, st.label),
  }
  if st.quest_id then parts[#parts + 1] = ":quest-id " .. st.quest_id end
  if st.stage then parts[#parts + 1] = ":stage " .. st.stage end
  local fl = {}
  for _, fid in ipairs(st.follows) do fl[#fl + 1] = string.format("%q", fid) end
  parts[#parts + 1] = ":follows [" .. table.concat(fl, " ") .. "]"
  parts[#parts + 1] = ":follows-mode :" .. st.mode
  return "    {" .. table.concat(parts, " ") .. "}"
end

local blocks = {}
for _, cid in ipairs(order) do
  local c = chains[cid]
  local steps = {}
  for _, st in ipairs(c.steps) do steps[#steps + 1] = step_fennel(st) end
  blocks[#blocks + 1] = string.format(
    [[ :%s {:id %q
        :name %q
        :kind :attunement
        :expac %q
        :faction %q
        :steps [
%s]}]],
    cid, cid, c.def.NAME, TBC, c.def.FACTION or "Both",
    table.concat(steps, "\n"))
end

os.execute("mkdir -p " .. OUT)
local body = string.format([[
;; src/domain/chains/data.fnl -- GENERATED by scripts/import-chains.lua. DO NOT EDIT.
;; Source: the Attune addon by Cixi (hippuli/Attune mirror; no upstream license,
;; risk accepted 2026-06-05 -- see CREDITS.md). Routina aggregate is GPL-3.0.
;; See vendor/chain-source/README.md. Regenerate: task vendor-chain-source && task import-chains.
;;
;; Pure data: chain-id -> schemas.ChainDef map (TBC attunement chains only,
;; steps gated to ## Interface %d), registered for src/domain/chains.fnl to
;; read and validate. No WoW API. Steps carry no :coord yet (Phase 9).

(local Routina (or _G.Routina {}))
(set _G.Routina Routina)

(local chain-data
       {%s})

(set Routina.chain-data chain-data)

chain-data
]], INTERFACE, table.concat(blocks, "\n"))
local f = assert(io.open(OUT .. "/data.fnl", "w"))
f:write(body)
f:close()

print(string.format(
  "chains: %d chains, %d steps  skipped: spacers=%d out-of-version=%d dup-ids=%d  pruned-follows=%d",
  #order, counts.steps, counts.spacers, counts.version_dropped,
  counts.duplicate_ids, counts.pruned_follows))
