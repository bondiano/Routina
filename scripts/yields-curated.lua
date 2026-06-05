-- yields-curated.lua -- hand-curated per-activity yield inputs (Phase 7).
-- Read by scripts/import-yields.lua together with the generated
-- vendor/bis-source/zone-bosses.lua; one entry per src/domain/activities.fnl
-- registry id. NOT shipped -- only the generated src/domain/yields/data.fnl is.
--
-- gold = {min, max} in COPPER per clear, per player (1g = 10000c). An honest
-- band (OQ-12 resolved 2026-06-05): curated v1 estimates spanning quest coin,
-- boss coin share, and vendorable trash for a typical PUG clear -- the truth
-- lives somewhere inside; at runtime the band tightens toward the player's own
-- recorded history (yields.blended-band).
--
-- badges = "bosses" -> count the zone's distinct bosses from zone-bosses.lua;
-- a number -> curated count. The derived rosters lump rares and named trash in
-- with real bosses (Karazhan "has" 21), so heroics carry curated counts -- the
-- badge-dropping roster is a well-known static fact (1 Badge of Justice per
-- heroic boss, incl. heroic-only extras like Blood Guard Porung). Raids are 0
-- in v1: 2.4-style raid badge drops are NOT assumed for Anniversary Phase 1 --
-- flip per activity once live data confirms them.
--
-- rep = {faction, amount} -- reputation payout of one clear, where the
-- activity is a rep hub (faction slugs match src/domain/ctx.fnl faction-ids).
return {
  ["karazhan"] = {zone = "Karazhan", badges = 0, gold = {150000, 450000}},
  ["serpentshrine-cavern"] = {zone = "Serpentshrine Cavern", badges = 0, gold = {200000, 600000}},
  ["tempest-keep"] = {zone = "Tempest Keep", badges = 0, gold = {200000, 550000}},
  ["black-temple"] = {zone = "Black Temple", badges = 0, gold = {250000, 700000}},
  ["hyjal-summit"] = {zone = "Hyjal Summit", badges = 0, gold = {300000, 800000}},
  ["gruuls-lair"] = {zone = "Gruul's Lair", badges = 0, gold = {80000, 250000}},
  ["magtheridons-lair"] = {zone = "Magtheridon's Lair", badges = 0, gold = {50000, 180000}},
  ["naxxramas"] = {zone = "Naxxramas", badges = 0, gold = {100000, 300000}},
  -- Heroic 5-mans: curated badge-dropping boss counts (1 badge per boss).
  -- Mechanar counts both Gatewatchers (the classic 5-badge run); Shattered
  -- Halls counts heroic-only Blood Guard Porung; Mana-Tombs excludes Yor
  -- (summoned via a repeatable quest, not a fixture of the clear).
  ["heroic-mech"] = {zone = "The Mechanar", badges = 5, gold = {100000, 250000}},
  ["heroic-slabs"] = {zone = "Auchenai Crypts", badges = 2, gold = {80000, 200000}},
  ["the-slave-pens"] = {zone = "The Slave Pens", badges = 3, gold = {90000, 220000}},
  ["the-shattered-halls"] = {zone = "The Shattered Halls", badges = 5, gold = {120000, 300000}},
  ["the-blood-furnace"] = {zone = "The Blood Furnace", badges = 3, gold = {90000, 220000}},
  ["shadow-labyrinth"] = {zone = "Shadow Labyrinth", badges = 4, gold = {110000, 280000}},
  ["mana-tombs"] = {zone = "Mana-Tombs", badges = 3, gold = {90000, 220000}},
  -- Daily circuits / rep hubs: deterministic quest coin, no badges.
  ["skettis-daily"] = {badges = 0, gold = {90000, 220000}},
  ["ogrila-dailies"] = {badges = 0, gold = {350000, 550000},
                        rep = {faction = "ogrila", amount = 1200}},
  -- Outdoor world bosses: coin share of one kill.
  ["shadowmoon-valley"] = {badges = 0, gold = {30000, 120000}},
  ["hellfire-peninsula"] = {badges = 0, gold = {30000, 120000}},
  -- Level-60 dungeons farmed at 70.
  ["dire-maul"] = {zone = "Dire Maul", badges = 0, gold = {150000, 500000}},
  ["blackrock-depths"] = {zone = "Blackrock Depths", badges = 0, gold = {120000, 400000}},
  -- Token sinks: showing up costs nothing and pays nothing.
  ["vendor"] = {badges = 0, gold = {0, 0}},
  ["quest"] = {badges = 0, gold = {0, 0}},
}
