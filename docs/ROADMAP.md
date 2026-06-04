# Routina -- Roadmap

> Weekly route planner with a BiS-aware probability engine for **WoW TBC Classic
> Anniversary**.
>
> This roadmap is a living document. Phases are sequential by *dependency*, not
> calendar -- a later phase may start once its prerequisites are merged, not
> when the previous phase is "fully" polished. Anything marked **[open]** is
> not yet committed and is fair game to challenge in review.

## Guiding principles

1. **Pure core, imperative shell.** Domain modules in `src/domain/` stay pure
   Fennel. WoW API, time, randomness, SavedVariables -- only in `src/core/` and
   `src/ui/`.
2. **Tests come with code.** Every domain change ships with a `_spec.fnl`.
   Target >=85% busted coverage on `src/domain/`.
3. **Read-only planning addon.** Never touch secure templates, never run in
   combat-locked code paths. Routina advises; the player acts.
4. **Phase the TOC, not the addon.** `## Interface: 20505` bumps only when a
   real content phase ships and has been smoke-tested.
5. **Small, sharp surface.** It is better to ship a tight weekly planner with
   trustworthy probabilities than a sprawling assistant that approximates.

## Status snapshot (2026-06-05)

| Area | State |
|---|---|
| Build pipeline (`task build/test/lint/package`) | Working |
| Fennel compiler vendored | `vendor/fennel.lua` pinned |
| Domain module: `drop-chance` | Shipped, used as canonical example |
| Tests: busted + Fennel searcher | Wired, 115 passing across core/domain/ui |
| WoW API mocks | Stub harness in `spec/mocks/wow-api.fnl` + `spec/mocks/ace3.fnl` |
| Ace3 wiring | **Done** -- `src/core/ace.fnl` (AceAddon entry, wires root + events) |
| Event dispatcher | **Done** -- `src/core/events.fnl` (`case` dispatch; `RAID_INSTANCE_WELCOME`/`PLAYER_LOGOUT` drive `weekly-state`) |
| Weekly-state | **Done** -- `src/domain/weekly-state.fnl` (pure; entered-raid tracking, seeded/flushed via `db.char` by events) |
| SavedVariables / AceDB | **Done** -- `src/core/saved-vars.fnl` (versioned, migration list) |
| Schemas + runtime validation | **Done** -- `src/domain/{schemas,validate}.fnl` |
| WoW API wrapper | **Done** -- `src/core/wow.fnl` |
| UI shell (custom CreateFrame, journal theme) | **Done** -- `root` + `theme` + `dom`/`format`/`frames`, three tab pills |
| Vertical slice (Plan tab) | **Done** -- `domain/plan.fnl` scores a `sample-catalog` scaffold, rendered by `tabs/weekly.fnl` |
| BiS catalog | `bis-catalog.fnl` + 27 generated `bis/<class>-<spec>.fnl` **done** (imported from GPL source; all 9 classes). **Phase 4b landed (pending in-game smoke):** full source ranks (~5100 entries), every entry carries `:kind` (`:bis`/`:pre-raid`) + `:rank`; queries `ranked-for-slot`/`pre-raid-for-slot`; route gearing-up mode + per-slot rank fallback; BiS tab tiers + pre-raid toggle. |
| Lockout / activity model | `lockouts.fnl` + `activities.fnl` **done** (busted-green); next: `drop-table`, `route` |
| License | **GPL-2.0** (inherited from imported BiS data; see `LICENSE`/`CREDITS.md`) |
| Drop table | `drop-table.fnl` + generated `drops/data.fnl` **done** (279 entries imported from nexus-devs MIT; OQ-1 resolved) |
| Routing engine | **Partial** -- `plan.fnl` proto scorer; real `route.plan-week` is Phase 2 (last domain piece: `route`) |
| Localization scaffold (`Locales/`) | Empty (`.gitkeep` only) |
| Release pipeline (BigWigs packager) | Configured, no tag yet |

## Phase 0 -- Scaffolding (DONE)

Goal: a clean clone can `task deps && task test && task build && task install`
and load an empty addon in-game.

- [x] Fennel -> Lua 5.1 build via `Taskfile.yml`
- [x] Pinned compiler in `vendor/`
- [x] busted spec harness with Fennel searcher (`spec/helper.lua`)
- [x] WoW API mock seed (`spec/mocks/wow-api.fnl`)
- [x] `.pkgmeta` + BigWigs packager dry run
- [x] Canonical pure domain example (`drop-chance.fnl` + spec)
- [x] `.claude/examples/` set of 7 worked patterns

## Phase 1 -- Foundation (CODE-COMPLETE, pending in-game smoke)

> All modules below are merged and green under `task lint && task test`. This
> phase flips to DONE only after the in-game smoke checks in the exit criteria
> pass on a live TBC Anniversary client.

Goal: the addon loads under Ace3, owns its DB, dispatches events, and exposes
a single root frame -- still without any planner logic. After this phase the
shape of every later file is fixed.

Order matters; later items depend on earlier.

1. **`src/core/ace.fnl`** -- AceAddon entry per
   `.claude/examples/04-ace-addon-module.fnl`. `OnInitialize` / `OnEnable`,
   addon namespace export.
2. **`src/core/saved-vars.fnl`** -- AceDB defaults, `db.version`, empty
   migration list. Schema versioned from day one.
3. **`src/core/events.fnl`** -- AceEvent dispatcher with a `case` table.
   Wraps every WoW event we will ever consume; domain modules subscribe to
   *its* events, never to WoW's directly. See
   `.claude/examples/03-event-dispatcher.fnl`.
4. **`src/core/wow.fnl`** -- thin wrapper around the WoW APIs we use
   (`GetServerTime`, `GetInstanceInfo`, `GetItemInfo`, ...). One place to
   stub from tests, one place to gate by client build. See
   `.claude/examples/02-wow-api-wrapper.fnl`.
5. **`src/domain/schemas.fnl`** -- declarative type definitions (Lockout,
   Activity, BisItem, RouteStep, ...). Drives runtime validation, docgen and
   test fixture generators. See `.claude/examples/07-type-contracts.fnl`.
6. **`src/domain/validate.fnl`** -- pure `check`/`coerce` over schemas;
   runs at module boundaries only, never in hot loops.
7. **`src/ui/root.fnl` + `src/ui/theme.fnl`** -- custom `CreateFrame`
   panel with header strip, three tab pills, and gear icon. No tab
   content yet. Toggled by `/routina`. Theme tokens declared as plain
   data; widget skeletons follow
   [.claude/examples/08-ui-widget.fnl](../.claude/examples/08-ui-widget.fnl).
   See [UI](UI.md) §2-5.
8. **`.toc` update** -- add `Libs\LibStub\LibStub.lua`, `Libs\Ace3\Ace3.xml`,
   the new `build/...` outputs, and `RoutinaDB` confirmed.
9. **README + `docs/api.md`** regenerated via `/docgen`.

Exit criteria:

- Addon loads on a clean WoW TBC Classic Anniversary install with no Lua
  errors and an empty UI panel.
- `task lint && task test` green; coverage >=85% on `src/domain/`.
- SavedVariables round-trip (write a value, `/reload`, read it back).

## Phase 2 -- Domain MVP (NEXT)

Goal: enough pure modules to *describe* a weekly plan, even if the UI is
ugly.

1. **`src/domain/lockouts.fnl`** -- DONE (pending in-game smoke)
   - Pure model of raid/dungeon lockouts: id, expiry timestamp, bosses
     killed/remaining, owner key. Operates on `schemas.LockoutView` (the
     planner projection; the raw WoW record stays `schemas.Lockout`).
   - Predicates: `lockout-active?`, `lockout-shareable?`, `time-until-reset`.
   - Fed by `src/core/events.fnl` via `UPDATE_INSTANCE_INFO`,
     `RAID_INSTANCE_WELCOME`, `RAID_BOSS_KILLED`.
2. **`src/domain/activities.fnl`** -- DONE (pending in-game smoke)
   - Registry of weekly content: raids, heroic dungeons, dailies, PvP weekly,
     reputation hubs. Static `ActivityDef` registry; `available?` consumes
     `lockouts` for per-period availability; `requirements-met?` checks a
     `schemas.Player` (level + attunements + reputations).
   - Each activity has `:id`, `:type`, `:reset` (`:weekly | :daily | :none`),
     `:length-estimate`, `:requirements`.
   - **OQ-4 resolved (2026-06-01):** reputations are modelled as weekly
     activities -- `:rep-hub` is a live type and `ActivityRequirements` carries
     an optional `:rep` gate. The multi-week "score per hour" warp is deferred
     to route scoring (§5 / OQ-6).
3. **`src/domain/bis-catalog.fnl`** + **`src/domain/bis/<class>-<spec>.fnl`** -- DONE
   - **Decision change:** instead of hand-curating via the `bis-catalog` macro,
     the catalog is **bulk-imported** by `scripts/import-bis.lua` (`task
     import-bis`) from the GPL-2.0 [BestInSlotTBCClassic] data vendored in
     `vendor/bis-source/` (item names from the MIT nexus-devs dataset). This
     relicenses Routina as **GPL-2.0** (see `LICENSE`, `CREDITS.md`).
   - 27 generated per-spec data modules (`bis/<class>-<spec>.fnl`, all 9 classes,
     26 source specs, ~820 entries at Priority 1-2) register into a shared
     accumulator; `bis-catalog.fnl` flattens + validates against
     `schemas.BisItem` and exposes `all` / `by-class-spec[-phase]` / `by-slot` /
     `primary-for-slot` / `specs-for-class`.
   - Source taxonomy is preserved verbatim (merged Holy/Disc priest, "Any" rogue,
     druid feral split). `:sources` is `:instance`-only (no boss/drop-rate
     upstream) until §4. Regenerate: `task vendor-bis-source && task import-bis`.
   - The `bis-curator` agent / macro remain for future hand-authored overlays.

   [BestInSlotTBCClassic]: https://github.com/Warkdev/BestInSlotTBCClassic
4. **`src/domain/drop-table.fnl`** -- DONE
   - Map `{:item-id -> {:source-activity :base-drop-p :boss :zone}}` (`:ml-pool`
     deferred to Phase 4 / OQ-3), with queries `for-item` / `drop-p` /
     `source-activity` / `all` / `by-activity`.
   - **OQ-1 resolved (2026-06-03):** generated by `scripts/import-drops.lua` from
     the MIT nexus-devs dataset (`source.category/name/zone/dropChance` +
     `zones.json`), scoped to the BiS catalog's items. Boss/Rare/Zone Drop →
     real `dropChance`; Vendor/Quest → `1.0`; crafted/token/sourceless omitted.
     279 entries → `src/domain/drops/data.fnl`. No Wowhead scraping.
   - Regenerate: `task vendor-bis-source && task import-drops`.
5. **`src/domain/route.fnl`**
   - `(plan-week player db) -> {:steps [...] :score number :est-minutes int}`.
   - Greedy scoring v1: for each candidate activity, sum
     `weight(slot) * drop-p(item, run)` over its BiS-relevant items and the
     player's current gear.
   - Uses `drop-chance.at-least-one` / `effective-rate` -- no new math.
6. **Property-based tests** for `route` and `drop-chance`. Generators in
   `spec/helpers/gen.fnl`.

Exit criteria:

- `(route.plan-week ...)` returns a deterministic plan for a fixture player
  with no WoW API calls and no time/random sources outside the seed.
- Domain coverage still >=85%.

## Phase 3 -- UI MVP

Goal: a player can open Routina, see what they have left this week, and
follow a recommended order. Visual language defined in [UI](UI.md):
parchment journal, custom `CreateFrame`, six MVP widgets.

Widgets first (order matters -- tabs compose widgets, not the reverse):

1. **`src/ui/widgets/chance-meter.fnl`** -- atomic probability bar.
   Canonical pattern in `.claude/examples/08-ui-widget.fnl`.
2. **`src/ui/widgets/item-pill.fnl`** -- item icon + name + chance-meter
   + tooltip. Used by `activity-card` and `bis-slot-row`.
3. **`src/ui/widgets/activity-card.fnl`** -- the atom of the Plan tab.
4. **`src/ui/widgets/lockout-timer.fnl`** -- throttled timer (1 Hz idle,
   4 Hz under 60 s). The only `OnUpdate` widget in the panel body.
5. **`src/ui/widgets/bis-slot-row.fnl`** -- the atom of the BiS tab,
   grouped by source activity.
6. **`src/ui/widgets/why-drawer.fnl`** -- slide-in explainer, replaces
   modal popups. Singleton, not pooled.

Then the tabs that compose them:

7. **`src/ui/tabs/weekly.fnl`** -- scrolling stack of `activity-card`,
   sorted by score desc, summary row at the tail.
8. **`src/ui/tabs/lockouts.fnl`** -- stack of `lockout-timer` rows,
   sorted by urgency (sourced from `lockouts` domain via events, never
   directly).
9. **`src/ui/tabs/bis.fnl`** -- `bis-slot-row` grouped by source
   activity, with a `progress-arc`-style header band.
10. **`src/ui/options.fnl`** -- AceConfig panel (only place AceGUI is
    allowed): spec override, ML competition assumption, weight tuning
    (1-5 per slot), reset behaviour, font scale.
11. **`src/ui/format.fnl`** -- pure formatters (probabilities, durations,
    reset-in). No widget code.

Exit criteria:

- Manual wowUnit smoke: open every tab, click `Why?` on a card, swap
  tabs while the drawer is open, change a setting, `/reload`, settings
  persisted. Checklist lives in [TESTING](TESTING.md#tier-2--wowunit-manual-pre-release).
- Tab switch median <16 ms, plan re-render <50 ms ([UI](UI.md) §10).
- No `print` calls anywhere; everything goes through `log:debug`.
- No hex colour literals in `src/ui/widgets/` -- only theme tokens.

## Phase 4 -- Probability engine v2

Once the pipeline is honest end-to-end, sharpen the math.

1. **Bayesian luck score** -- pure model + live recording **DONE** (experimental,
   pending in-game smoke):
   - `src/domain/history.fnl` -- pure cumulative log (`record-run` / `record-drop`
     / `runs-for` / `drops-for` / `luck` -> `drop-chance.bayesian-luck`, with a
     runs>=drops clamp; `normalize`/`to-db` for SavedVariables). Persisted at
     `db.char.history`; the shell seeds it on first use and flushes on
     `PLAYER_LOGOUT`.
   - Events wired (signatures verified on warcraft.wiki.gg, all TBC 2.5.5-valid):
     **ENCOUNTER_END** (`encounterID, encounterName, difficultyID, groupSize,
     success`) tallies a per-boss trial on a kill; **CHAT_MSG_LOOT** tallies a
     drop for the player's own loot (`wow.self-loot?`) of a tracked item
     (`wow.loot-item-id` -> `drop-table.for-item`). Both are always registered but
     inert until the **off-by-default** options toggle "Track loot luck
     (experimental)" calls `set-history-tracking!`.
   - **Remaining (not a blocker):** validate that ENCOUNTER_END's `encounterName`
     matches the `drop-table` `:boss` strings (the runs key) against live data,
     and surface the luck score in the UI (why-drawer) once real history exists.
2. **ML competition modelling** -- per-activity `competitors-by-role` map,
   exposed in options. `effective-rate` flows through `route` scoring.
3. **Monte Carlo route projection** -- **DONE** (pending in-game smoke):
   `route.project-week` collapses each plan step's target items into a per-slot
   "any upgrade by reset" Bernoulli (`drop-chance.at-least-one` + complement
   product) and samples it via `drop-chance.coupon-collector-mc`, returning
   P10/P50/P90 of "slots filled by reset" + the slot count. Pure + seeded
   (`drop-chance.make-rng`, MINSTD; 1000 sims). The seed is user-controlled via
   the options panel (`Projection seed`, 1..9999) -> `RouteContext.seed`; the Plan
   tab renders the projection as a tail summary card (pure `weekly.projection-view-model`).
4. **Recommendation diff** -- **DONE** (pending in-game smoke): the why-drawer's
   pure `view-model` now takes the next-best alternative the focused step
   out-scores and emits a `:diff` -- score delta, top-3 contributing items, and
   plain-English reasons (strongest item, weighted slot, shorter run). The Plan
   tab passes each card's rank+1 neighbour through `root.show-why!`; the drawer
   renders a "Why over B" section. Lockout decay is still flat (OQ-7), so it is
   not yet a differentiator in the diff.

Exit criteria:

- Adjusting "competitors on caster trinket" in options visibly reorders the
  weekly plan.
- Monte Carlo runs in <50 ms for a realistic week on a mid-range laptop.

## Phase 4b -- Catalog depth: pre-BiS & ranked alternatives (CODE-COMPLETE, pending in-game smoke)

> All five steps below are merged and green under `task lint && task test` (339
> specs). Flips to DONE after the BiS-tab smoke checks (toggle swaps the list,
> alternatives render, no Lua error) pass on a live client. As shipped:
> schema `:kind`/`:rank`; importer at full rank (~5100 entries, kind from
> Raid/WorldBoss/TokenId); catalog `ranked-for-slot`/`pre-raid-for-slot` + `?kind`
> on `by-class-spec-phase`; route additive gearing-up (`gearing-up?` at 50% of
> endgame `:bis` slots) + per-slot complement-product scoring so alternatives
> back each other up without double-counting; BiS tab primary+alternatives
> (display capped at 3, OQ-9) with a Best-in-slot / Road-to-BiS Dropdown.
>
> Dependency-gated, not calendar-gated: builds on the Phase 2 catalog/route and
> Phase 4 scoring, and may land **before** the Phase 6 release -- it directly
> sharpens G1/G2 (what to run, with the right targets). Today the catalog is
> **one item per slot, raid-BiS only**: `bis/<class>-<spec>.fnl` carries
> Priority 1-2 (`MAX_PRIORITY = 2` in `scripts/import-bis.lua`) and the BiS tab's
> `best-in` collapses each slot to the single highest-phase entry. A player
> gearing toward BiS sees only the destination, never the road, and never a
> second-best option when the drop won't come.

Goal: model two axes the source already supports but we currently discard --
**rank** (the tier-2/tier-N alternatives within a slot) and **kind** (pre-raid
catch-up gear vs endgame raid BiS) -- then surface both in scoring and the BiS
tab. Decisions locked (2026-06-05): a new orthogonal `:kind` field; import
**all** source ranks; pre-BiS and alternatives **feed** route scoring.

Order matters; later items depend on earlier.

1. **Schema -- `src/domain/schemas.fnl`** (schema change; see CLAUDE.md "Ask").
   Extend `schemas.BisItem` with two fields:
   - `:kind [:enum :pre-raid :bis]` -- provenance class of the recommendation,
     **orthogonal** to `:phase`. `:bis` = endgame raid/world-boss/token target;
     `:pre-raid` = catch-up gear to wear *toward* that BiS (dungeon, heroic,
     crafted, reputation, quest, PvP, BoE) at the slot's entry phase.
   - `:rank :integer` (>= 1) -- within `(class, spec, phase, kind, slot)`,
     1 = best. Maps directly to the source's `Priority`.
   - Bump `db.version` only if a SavedVariables-resident shape changes; the
     catalog itself is generated data, so this is a schema+validate+docgen
     change, not a migration. Regenerate `docs/api.md` via `/docgen`.

2. **Importer -- `scripts/import-bis.lua`** (regenerates all 27 data modules).
   - **Rank:** raise `MAX_PRIORITY` to import every source rank, emitting
     `:rank = Priority`. **Cost:** the source's `Priority` tail runs to 30
     (~6000+ links vs today's ~820 at Priority 1-2) -- roughly a 7-8x blow-up in
     generated data. Mitigations: (a) generated data modules are exempt from the
     300-line rule, but reviewability still suffers -- split per-spec files by
     phase (`bis/<class>-<spec>-p<phase>.fnl`) if any single file gets unwieldy;
     (b) measure load time -- the catalog flattens at module load, and 6k entries
     through `validate.check` once is fine, but confirm it stays off the frame.
   - **Kind:** the source has **no explicit pre-raid list** (`items.lua` Phase
     values are 1-5, never 0). Derive `:kind` from provenance: `Raid = true` or
     `WorldBoss = true` or token/tier currency -> `:bis`; everything else at the
     slot's entry phase (dungeon/heroic/crafted/rep/quest/vendor/PvP/BoE, joined
     via the already-vendored `item-sources.lua` `category`) -> `:pre-raid`. The
     exact rule is **OQ-8** (below) -- get it reviewed before regenerating.

3. **Catalog queries -- `src/domain/bis-catalog.fnl`.**
   - `by-class-spec-phase` gains an optional `?kind` (defaults to `:bis` to keep
     callers behaving as today).
   - New `M.ranked-for-slot [class spec phase slot ?kind]` -> `[BisItem]` sorted
     by `:rank` (primary first, then alternatives).
   - New `M.pre-raid-for-slot [class spec slot]` -> ranked pre-raid options.
   - `primary-for-slot` pins to `:kind :bis`, `:rank 1`.
   - All queries stay pure; extend `bis-catalog_spec.fnl` in the same change.

4. **Route scoring -- `src/domain/route.fnl`.**
   - **Alternatives as fallback:** a slot's "fill by reset" probability is
     `at-least-one` over the complement product of *all* ranked drops for that
     slot, not just rank 1 -- reusing `drop-chance.at-least-one` /
     `effective-rate`, no new math. Dedup per slot so alternatives never count as
     extra slots.
   - **Gearing-up mode:** when the player owns few `:bis` slots (a tunable
     threshold), target `:pre-raid` items so the weekly plan points at the
     dungeons/heroics/rep that actually move a fresh-70 forward; cross over to
     `:bis` targets as slots fill. Mode is derived from owned-set, not a manual
     toggle, so the plan stays "one screen, no config" (UX principle §9).
   - Property tests in `spec/helpers/gen.fnl`-backed `route_spec.fnl` for the
     fallback complement and the mode crossover.

5. **BiS tab -- `src/ui/tabs/bis.fnl` + `view-model`.**
   - Replace `best-in` (highest-phase collapse) with a kind+rank-aware select:
     per slot, a primary row (rank 1) plus an expandable list of alternatives
     (rank 2..N), each flagged owned/unowned.
   - A segmented control at the tab head: **Road to BiS (pre-raid)** vs
     **Phase N BiS** -- switches the whole checklist's `:kind`. Built only from
     AceGUI primitives via the `src/ui/acegui.fnl` facade (verify the widget
     exists in `Libs/Ace3/AceGUI-3.0/`; fall back via `acegui.registered?`).
   - Keep the pure data->view-model split (`M.list-view-model`) busted-tested;
     building widgets stays imperative / wowUnit-tier.

Exit criteria:

- BiS tab shows, for a fixture spec, a primary + >= 1 ranked alternative per
  populated slot, and the pre-raid/Phase toggle swaps the list with no Lua error.
- For a fresh-70 fixture (few `:bis` slots owned), `route.plan-week` surfaces
  `:pre-raid` targets; for a near-BiS fixture it surfaces `:bis` targets --
  deterministic, no WoW API, seed-controlled.
- Domain coverage still >= 85%; `docs/api.md` regenerated and CI-clean.
- Catalog load (flatten + validate of the full-rank set) stays off the render
  frame -- measured, not assumed.

Open questions this phase introduced (shipped with a v1 answer; revisit if
in-game data contradicts it -- still worth promoting to [PRD §13](PRD.md#13-open-questions)):

- **OQ-8 -- pre-raid derivation.** *v1 answer (shipped):* the source has no
  pre-raid list, so `kind_of` in `scripts/import-bis.lua` synthesises it from the
  Warkdev item flags -- `Raid or WorldBoss or TokenId>0 -> :bis`, else
  `:pre-raid` (~2475 `:bis` / ~2627 `:pre-raid`). The `item-sources.lua category`
  refinement and a hand-authored overlay (the `bis-curator` path) stay open if
  live data shows the flags lying for some specs. *Affects:* importer, catalog
  correctness.
- **OQ-9 -- alternatives depth.** *v1 answer (shipped):* data keeps every rank;
  the surfaces cap. The BiS tab shows primary + 3 alternatives (`max-alts`);
  route admits the full rank set per slot but its scorer combines them per-slot
  (complement product), so the Priority-20+ tail can't inflate a slot's value.
  Still open: whether to additionally drop the BoE/vendor long tail by relevance
  rather than position. *Affects:* BiS tab, route candidate set, perf.

## Phase 5 -- Polish

Parallelizable; pick up alongside Phase 3-4 as time allows.

- **Localization** -- `Locales/enUS.lua` first, AceLocale wiring, ruRU
  pulled from translator after string freeze.
- **Theming** -- light/dark, font scale, colour-blind safe palette for the
  weekly tab.
- **Profiles** -- AceDBOptions, per-character + shared profile.
- **Slash commands** -- `/routina`, `/rt`, `/rt plan`, `/rt reset`,
  `/rt debug`. Documented in `README.md`.
- **`/docgen` in CI** -- `docs/api.md` stays in sync; CI fails on drift.
- **Performance budget** -- `task profile` task: assert `route.plan-week`
  under 5 ms median over 100 fixture players.

## Phase 6 -- Release 1.0 (TBC Anniversary Phase 1)

- Full wowUnit smoke suite, manually executed pre-tag.
- BigWigs packager release run, signed against `## Interface: 20505`.
- CurseForge + Wago listings, screenshots, short demo gif.
- User-facing docs: `docs/USER_GUIDE.md` (install, first-run, FAQ).
- Tag `v1.0.0`, write release notes from the milestone.

## Phase 7+ -- Post-1.0 (sketch, **[open]**)

- TBC Classic Anniversary **Phase 2** content (`## Interface` bump only
  after smoke testing on a Phase 2 PTR client).
- Heroic dungeon optimizer (path-find shortest reputation + BiS run).
- Group-aware planning: import a guild signup, compute likely loot share.
- Share / export plans as a string between alts or guildmates.
- Optional Wago / WeakAuras hook for "next activity" reminder.
- Mythic+ analogue? Probably out of scope for TBC -- park it.

## Open questions

Open product questions live in [PRD §13](PRD.md#13-open-questions) -- not
duplicated here. When an OQ-N gets answered, move the resolution into the
relevant phase above as a concrete task and strike the entry in PRD §13.

## Non-goals (for now)

Stated up front so we don't accidentally re-litigate them.

- Combat or rotation advice. Routina is a *planner*, not a DPS meter.
- Auction house / gold optimization.
- Retail WoW support. Lua 5.1 + TBC Classic API only.
- Cloud sync, account-bound storage outside SavedVariables.
- Any AI / LLM call from inside the addon at runtime.

## How to update this file

- A phase becomes "DONE" only when its exit criteria are all green in CI and
  it has been smoke-tested in game (wowUnit or manual).
- Moving an item between phases is fine; rewriting an exit criterion after
  the fact is not -- add a follow-up task instead so the slip is visible.
- Update the **Status snapshot** date when you touch this file.
- Run `task lint && task test` before committing roadmap-adjacent code so
  the snapshot stays honest.
