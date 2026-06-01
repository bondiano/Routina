# Credits

## Bundled artwork

- **`Art/Parchment.tga`** -- the parchment-page texture used for the
  panel backdrop. Sourced from
  [Peterodox / YUI-Dialogue](https://github.com/Peterodox/YUI-Dialogue),
  file `Art/Theme_Brown/Parchment.png`, converted to uncompressed TGA
  for WoW Classic compatibility (`magick Parchment.png -compress none
  Parchment.tga`). Image content unmodified; only the container
  format changed. Attribution and gratitude to Peterodox.

- **`Art/OptionBackground-Hollow.tga`** -- the hand-painted hollow
  parchment cell-border framing each item row in the weekly plan.
  Sourced from
  [Peterodox / YUI-Dialogue](https://github.com/Peterodox/YUI-Dialogue),
  file `Art/Theme_Brown/OptionBackground-Hollow.png`, converted to
  uncompressed 32-bit TGA for WoW Classic compatibility (`magick
  OptionBackground-Hollow.png -alpha on -type TrueColorAlpha -depth 8
  -compress none OptionBackground-Hollow.tga`). Image content
  unmodified; only the container format changed. Attribution and
  gratitude to Peterodox.

  If the original author would prefer these assets removed or replaced,
  open an issue on the Routina repository and we will swap them for a
  CC0 alternative in the next release.

## BiS catalog data

Routina's Best-in-Slot catalog (`src/domain/bis/*.fnl`, aggregated by
`src/domain/bis-catalog.fnl`) is **generated** from third-party data by
`scripts/import-bis.lua` (`task import-bis`). The pinned source snapshots live in
`vendor/bis-source/` (see its `README.md` for commit SHAs).

- **BiS item selections** are derived from
  [Warkdev / BestInSlotTBCClassic](https://github.com/Warkdev/BestInSlotTBCClassic)
  (`data/bis_data.lua`, `data/items.lua`, `data/class.lua`,
  `data/inventoryslot.lua`; spec mapping transcribed from `modules/manager.lua`).
  That project is licensed **GPL-2.0**; because Routina redistributes a work
  derived from it, **Routina is itself licensed GPL-2.0** (see root `LICENSE`).
  Its license text is preserved verbatim at `vendor/bis-source/LICENSE.warkdev.txt`.
  Gratitude to Warkdev and contributors.
- **Item names** (id → name) are derived from
  [nexus-devs / wow-classic-items](https://github.com/nexus-devs/wow-classic-items)
  (`data/json/data.json`), which is **MIT**-licensed.

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
