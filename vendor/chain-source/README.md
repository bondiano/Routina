# Vendored chain source data

Routina's quest/attunement chain registry (`src/domain/chains/data.fnl`,
read by `src/domain/chains.fnl`) is **generated** from the data snapshot in
this directory by `scripts/import-chains.lua` (`task import-chains`). Refresh
the snapshot with `task vendor-chain-source`.

## Provenance

| File | Upstream | License | Pinned commit |
|---|---|---|---|
| `AttuneData.lua` | [hippuli/Attune](https://github.com/hippuli/Attune) `AttuneData.lua` (the Attune addon by Cixi@Remulos) | **none published** | `6db364737b054be2b6bbf432a7420f62e2c84928` |

The upstream Attune addon ships **no license file**; a strict reading makes
redistribution all-rights-reserved. The owner explicitly accepted this risk
on 2026-06-05 (see `CREDITS.md` and PRD OQ-10). Gratitude to Cixi and the
Attune contributors -- if the upstream author objects, this data will be
removed and re-curated by hand.

The import keeps only `EXPAC == "The Burning Crusade"` attunes, drops
`Spacer` steps, and gates patch-variant steps (`VALIDFROM`/`VALIDTO`) to the
`## Interface` number in `Routina.toc`. Attune data carries **no
coordinates**; chain-step waypoints (ROADMAP Phase 9) need a separate
source.
