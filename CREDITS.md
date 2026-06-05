# Credits

## Libraries

- **AceGUI-3.0: SFX Widgets**
  ([SFX-WoW / AceGUI-3.0_SFX-Widgets](https://github.com/SFX-WoW/AceGUI-3.0_SFX-Widgets),
  by StormFX) -- extra AceGUI widget types (`SFX-Header`, `SFX-Info`) used by the
  why-drawer and the options panel. Fetched into `Libs/AceGUI-3.0_SFX-Widgets`
  by `task libs` / the BigWigs packager (see `.pkgmeta`); not committed.

## Bundled artwork

- *None.* The previously bundled parchment textures (`Art/Parchment.tga`,
  `Art/OptionBackground-Hollow.tga`, from
  [Peterodox / YUI-Dialogue](https://github.com/Peterodox/YUI-Dialogue)) were
  removed when the panel migrated to AceGUI-3.0, which owns its own backdrop.
  Routina no longer ships bespoke art.

## BiS catalog data

Routina's Best-in-Slot catalog (`src/domain/bis/*.fnl`, aggregated by
`src/domain/bis-catalog.fnl`) is **generated** from third-party data by
`scripts/import-bis.lua` (`task import-bis`). The pinned source snapshots live in
`vendor/bis-source/` (see its `README.md` for commit SHAs).

- **BiS item selections** are derived from
  [Warkdev / BestInSlotTBCClassic](https://github.com/Warkdev/BestInSlotTBCClassic)
  (`data/bis_data.lua`, `data/items.lua`, `data/class.lua`,
  `data/inventoryslot.lua`; spec mapping transcribed from `modules/manager.lua`).
  That project is licensed **GPL-2.0**; Routina redistributes a work derived
  from it under **GPL-3.0** (see root `LICENSE`; relicensed from GPL-2.0 on
  2026-06-05). *Known, accepted risk:* the upstream grant does not state
  "or any later version", so a strict GPL-2.0-only reading would conflict
  with the GPL-3.0 aggregate -- the owner accepted this risk explicitly.
  Its license text is preserved verbatim at `vendor/bis-source/LICENSE.warkdev.txt`.
  Gratitude to Warkdev and contributors.
- **Item names** (id → name) and **drop rates + sources** (the `drop-table`:
  per-item drop chance, boss, and source zone) are derived from
  [nexus-devs / wow-classic-items](https://github.com/nexus-devs/wow-classic-items)
  (`data/json/data.json` + `zones.json`), which is **MIT**-licensed.

The source taxonomy is preserved verbatim, including its quirks (a merged
Holy/Discipline priest set, one "Any" rogue spec, the druid feral tank/dps
split). Drop-rate and per-boss source data are **not** present upstream; catalog
entries carry only an `:instance` derived from the source's
raid/world-boss/reputation flags until the Phase 2 drop-table lands.

## Vendored libraries

- **Ace3** suite (AceAddon, AceDB, AceEvent, AceConfig, AceLocale,
  AceDBOptions). Fetched at package time via `.pkgmeta` externals;
  see [WoWAce / Ace3](https://www.wowace.com/projects/ace3).
- **LibStub** -- standard addon-shared library loader.
- **CallbackHandler-1.0** -- the event-emitter shared across Ace3.

## Fonts

Routina uses the WoW client's built-in `FRIZQT__.TTF` and `ARIALN.TTF`.
No fonts are bundled or vendored.
