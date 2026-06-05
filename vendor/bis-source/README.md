# Vendored BiS source data

Routina's BiS catalog (`src/domain/bis/*.fnl`, aggregated by
`src/domain/bis-catalog.fnl`) is **generated** from the data snapshots in this
directory by `scripts/import-bis.lua` (`task import-bis`). Refresh the snapshot
with `task vendor-bis-source`.

## Provenance

| File | Upstream | License | Pinned commit |
|---|---|---|---|
| `bis_data.lua` | [Warkdev/BestInSlotTBCClassic](https://github.com/Warkdev/BestInSlotTBCClassic) `data/bis_data.lua` | GPL-2.0 | `4875cc1096e4a276bb2cf55709993d5c5269be08` |
| `items.lua` | same, `data/items.lua` | GPL-2.0 | same |
| `class.lua` | same, `data/class.lua` | GPL-2.0 | same |
| `inventoryslot.lua` | same, `data/inventoryslot.lua` | GPL-2.0 | same |
| `LICENSE.warkdev.txt` | same, `LICENSE.txt` (verbatim) | GPL-2.0 | same |
| `item-names.lua` | derived (id→name) from [nexus-devs/wow-classic-items](https://github.com/nexus-devs/wow-classic-items) `data/json/data.json` | MIT | `8339771805564c6de7850ff9428be8e841f69622` |
| `item-sources.lua` | derived (id→{category,boss,zone,dropChance}) from nexus-devs `data/json/data.json` + `zones.json` | MIT | `8339771805564c6de7850ff9428be8e841f69622` |

The spec-id → spec-name mapping used by the importer is hand-transcribed from the
same Warkdev addon's `modules/manager.lua` (`BIS_dataSpecs` / `BIS_specsFileToSpecs`);
it is encoded directly in `scripts/import-bis.lua` because that file pulls in WoW
API globals and cannot be `dofile`-d standalone.

Routina redistributes a work derived from the GPL-2.0 Warkdev data; the
Routina project itself is licensed GPL-3.0 (see root `LICENSE`, relicensed
from GPL-2.0 on 2026-06-05 -- the compatibility risk of a GPL-2.0-only
upstream reading is noted and accepted in `CREDITS.md`). `item-names.lua` is a
factual id→name map derived from the MIT-licensed nexus-devs dataset.
