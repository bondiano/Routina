# Routina -- Roadmap

> Weekly *routine* planner for **WoW TBC Classic Anniversary**: a BiS-aware
> probability engine plus attunement/quest chains, badge & gold goals,
> player-authored plans, and TomTom waypoints (scope expanded 2026-06-05,
> see "Scope expansion" below).
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
   The 2026-06-05 scope expansion grows the surface *by whole phases*, not by
   blur -- each phase still ships sharp, tested, and honest about its numbers.
6. **Soft-deps degrade gracefully.** TomTom, TSM, Auctionator are optional
   integrations behind headless-safe facades (the `src/ui/acegui.fnl`
   pattern): present -> richer behaviour, absent -> silent no-op, never a
   hard requirement, never a Lua error.

## Status snapshot (2026-06-06)

| Area | State |
|---|---|
| Build pipeline (`task build/test/lint/package`) | Working |
| Fennel compiler vendored | `vendor/fennel.lua` pinned |
| Domain module: `drop-chance` | Shipped, used as canonical example |
| Tests: busted + Fennel searcher | Wired, 377 passing across core/domain/ui |
| Slash commands | **Done** -- `/routina`/`/rt` toggle, `options`, `plan`, `reset`, `debug` (PRD §6.6) |
| Performance budget | **Done** -- `task profile`: `route.plan-week` ~1.4 ms median over 100 fixture players (M5 budget 5 ms) |
| WoW API mocks | Stub harness in `spec/mocks/wow-api.fnl` + `spec/mocks/ace3.fnl` |
| Ace3 wiring | **Done** -- `src/core/ace.fnl` (AceAddon entry, wires root + events) |
| Event dispatcher | **Done** -- `src/core/events.fnl` (`case` dispatch; `RAID_INSTANCE_WELCOME`/`PLAYER_LOGOUT` drive `weekly-state`) |
| Weekly-state | **Done** -- `src/domain/weekly-state.fnl` (pure; entered-raid tracking, seeded/flushed via `db.char` by events) |
| SavedVariables / AceDB | **Done** -- `src/core/saved-vars.fnl` (versioned, migration list) |
| Schemas + runtime validation | **Done** -- `src/domain/{schemas,validate}.fnl` |
| WoW API wrapper | **Done** -- `src/core/wow.fnl` |
| UI shell | **Done** -- rebuilt on **AceGUI-3.0 + SFX-Widgets** via the `src/ui/acegui.fnl` facade (parchment/custom stack retired); tinted `Frame` + `TabGroup` root, theme tokens bridged |
| UI widgets (custom `CreateFrame` exceptions) | **Done** -- `chance-meter`, `lockout-timer` (only `OnUpdate`), `why-drawer` (singleton); everything else is AceGUI + pure view-models |
| Vertical slice (Plan tab) | **Done** -- `tabs/weekly.fnl` renders real `route.plan-week` steps + `project-week` tail card via `src/core/planner.fnl` |
| Options panel | **Done** -- AceConfig, split into Blizzard sub-panels (General / Slot weights / Attunement gating / Profiles, `childGroups :tree`) |
| BiS catalog | `bis-catalog.fnl` + 27 generated `bis/<class>-<spec>.fnl` **done** (imported from GPL source; all 9 classes). **Phase 4b landed (pending in-game smoke):** full source ranks (~5100 entries), every entry carries `:kind` (`:bis`/`:pre-raid`) + `:rank`; queries `ranked-for-slot`/`pre-raid-for-slot`; route gearing-up mode + per-slot rank fallback; BiS tab tiers + pre-raid toggle. |
| Lockout / activity model | `lockouts.fnl` + `activities.fnl` **done** (busted-green); next: `drop-table`, `route` |
| License | **GPL-2.0** (inherited from imported BiS data; see `LICENSE`/`CREDITS.md`) |
| Drop table | `drop-table.fnl` + generated `drops/data.fnl` **done** (279 entries imported from nexus-devs MIT; OQ-1 resolved) |
| Routing engine | **Done** -- `route.fnl` (`plan-week` greedy scorer through `effective-rate`, gearing-up mode, `project-week` Monte Carlo) + `ctx.fnl` context builder; property-tested via `spec/helpers/gen.fnl` |
| Competition model | **Done** -- `competition.fnl` by-role model (PRD OQ-3 resolved): catalog-derived contending roles x raid composition, scaled by `ActivityDef :group-size`; "Raid composition" options sub-panel |
| Localization scaffold (`Locales/`) | Empty (`.gitkeep` only) |
| Release pipeline (BigWigs packager) | Configured, no tag yet |
| Quest / chain engine | **Phase 6 CODE-COMPLETE (pending in-game smoke)** -- schemas + generated Attune data (23 TBC chains, 415 steps) + pure `chains.fnl` + QUEST_TURNED_IN wiring + derived attunement gates + plan advisory + Chains tab; relicensed GPL-3.0 |
| Goal targets (badges / gold / rep) | **Phase 7 CODE-COMPLETE (pending in-game smoke)** -- yields data (badges + honest gold bands, OQ-12) + pure `goals.fnl` (deadline-aware urgency, OQ-11; resolves OQ-6) + route/ctx integration + per-visit yield tracking (PLAYER_MONEY/badge loot, db v3) + TSM/Auctionator price facade + Plan-tab goal cards & Goals options sub-panel |
| Player-authored plans | **Not started** (Phase 8) |
| Waypoints / TomTom | **Not started** (Phase 9); no coordinate model in domain yet |

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

## Phase 2 -- Domain MVP (CODE-COMPLETE, pending in-game smoke)

> All modules below are merged and green under `task lint && task test`. The
> CI-level exit criteria pass; the phase flips to DONE together with Phase 1's
> in-game smoke (the domain is exercised live through the Plan tab).

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
5. **`src/domain/route.fnl`** -- DONE
   - `(plan-week player ctx) -> {:steps [...] :score number :est-minutes int}`.
   - Greedy scoring v1: for each candidate activity, per-slot complement
     product of its BiS-relevant ranked drops against the player's current
     gear, weighted by slot (see Phase 4b §4 for the gearing-up extension).
   - Uses `drop-chance.at-least-one` / `effective-rate` -- no new math.
   - `RouteContext` is built by the pure `src/domain/ctx.fnl` from db + player
     and fed by the `src/core/planner.fnl` shell.
6. **Property-based tests** for `route` and `drop-chance` -- DONE. Generators
   in `spec/helpers/gen.fnl`.

Exit criteria:

- `(route.plan-week ...)` returns a deterministic plan for a fixture player
  with no WoW API calls and no time/random sources outside the seed.
- Domain coverage still >=85%.

## Phase 3 -- UI MVP (CODE-COMPLETE, pending wowUnit smoke)

> **Decision change (shipped):** the parchment journal / bespoke
> `CreateFrame`-widget stack this phase originally planned was replaced by
> **AceGUI-3.0 + SFX-Widgets** through the `src/ui/acegui.fnl` facade -- the
> parchment bitmap was un-themeable at arbitrary sizes ([UI](UI.md) has the
> full rules). Three of the six planned widgets (`item-pill`,
> `activity-card`, `bis-slot-row`) were **retired as widgets**: their data
> shaping lives on as pure, busted-tested view-models rendered into AceGUI
> containers; only what AceGUI cannot do stayed custom `CreateFrame`. The
> phase flips to DONE after the wowUnit smoke checklist in the exit criteria
> passes on a live client.

Goal: a player can open Routina, see what they have left this week, and
follow a recommended order. Visual language defined in [UI](UI.md).

Widgets first (order matters -- tabs compose widgets, not the reverse):

1. **`src/ui/widgets/chance-meter.fnl`** -- DONE. Atomic probability bar;
   custom `CreateFrame` (justified: AceGUI has no proportional meter).
2. **`src/ui/widgets/item-pill.fnl`** -- RETIRED (AceGUI migration). Item
   rows are AceGUI labels built from the pure card/list view-models;
   tooltips via `GameTooltip:SetItemByID`.
3. **`src/ui/widgets/activity-card.fnl`** -- RETIRED (AceGUI migration).
   The Plan tab's atom is the pure `card-view-model` rendered into an
   AceGUI group per step.
4. **`src/ui/widgets/lockout-timer.fnl`** -- DONE. Throttled timer (1 Hz
   idle, 4 Hz under 60 s). The only `OnUpdate` widget in the panel body.
5. **`src/ui/widgets/bis-slot-row.fnl`** -- RETIRED (AceGUI migration).
   The BiS tab builds slot rows from its pure `list-view-model`
   (primary + ranked alternatives, Phase 4b §5).
6. **`src/ui/widgets/why-drawer.fnl`** -- DONE. Slide-in explainer,
   replaces modal popups. Singleton, not pooled; pure `view-model`
   (including the Phase 4 recommendation diff).

Then the tabs that compose them:

7. **`src/ui/tabs/weekly.fnl`** -- DONE. Scrolling stack of step cards,
   sorted by score desc, `project-week` summary card at the tail.
8. **`src/ui/tabs/lockouts.fnl`** -- DONE. Stack of `lockout-timer` rows,
   sorted by urgency (sourced from `lockouts` domain via events, never
   directly).
9. **`src/ui/tabs/bis.fnl`** -- DONE. Slot checklist grouped by source
   activity, Best-in-slot / Road-to-BiS dropdown (Phase 4b §5).
10. **`src/ui/options.fnl`** -- DONE. AceConfig panel: spec override, ML
    competition assumption, weight tuning (1-5 per slot), attunement
    gating, projection seed, luck tracking toggle, profiles. Split into
    Blizzard sub-panels (General / Slot weights / Attunement gating /
    Profiles via `childGroups :tree`) after one flat page overflowed the
    fixed-size Blizzard options frame. The originally-planned reset-behaviour
    and font-scale knobs did not ship here -- font scale folds into Phase 5
    theming; reset behaviour is a follow-up once a real need shows up.
11. **`src/ui/format.fnl`** -- DONE. Pure formatters (probabilities,
    durations, reset-in). No widget code.

Exit criteria:

- Manual wowUnit smoke: open every tab, click `Why?` on a card, swap
  tabs while the drawer is open, change a setting, `/reload`, settings
  persisted. Checklist lives in [TESTING](TESTING.md#tier-2--wowunit-manual-pre-release).
- Tab switch median <16 ms, plan re-render <50 ms ([UI](UI.md) §10).
- No `print` calls anywhere; everything goes through `log:debug`.
- No hex colour literals in `src/ui/widgets/` -- only theme tokens.

## Phase 4 -- Probability engine v2 (CODE-COMPLETE, pending in-game smoke)

Once the pipeline is honest end-to-end, sharpen the math. All four items are
merged and green under `task lint && task test`; the phase flips to DONE with
the in-game smoke pass.

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
2. **ML competition modelling** -- **DONE (pending in-game smoke; resolves
   PRD OQ-3).** Competition is modelled **by role** from a single player-
   declared raid composition rather than the originally-sketched per-activity
   map: the new pure `src/domain/competition.fnl` holds the 27-entry
   spec->role table and lazily folds the BiS catalog into an item-id ->
   contending-roles index, so "who rolls on this drop" is derived, never
   curated. `route.competitors-for` is per-item now, with precedence:
   explicit per-activity override > uncontested-type exemption (vendor /
   quest / daily / rep-hub never divide their guaranteed pickups -- a
   deliberate fix) > composition scaled to the activity's new
   `ActivityDef :group-size` (Kara 10 / 25-mans / Naxx 40 / 5-mans) >
   global `default-competitors` slider > 1. Options gained a "Raid
   composition" Blizzard sub-panel (5 role sliders, first-touch opt-in, full
   back-compat while unset). The exit criterion is now a busted regression:
   more casters in a same-size raid lowers a caster cloak's chance and
   reorders, while swapping non-contending roles changes nothing.
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
> Phase 4 scoring, and may land **before** the Phase 10 release -- it directly
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
- **Profiles** -- DONE early: AceDBOptions sub-panel shipped with the
  Phase 3 options split (per-character + shared profile).
- **Slash commands** -- DONE: `/routina` + `/rt` (toggle) and `... options`
  shipped with Phase 1; `/rt plan` (chat print via the pure
  `format.plan-lines`), `/rt reset` (luck history via `events.reset-history!`)
  and `/rt debug` (diagnostics via `format.debug-lines`) shipped with this
  phase and documented in `README.md`.
- **`/docgen` in CI** -- `docs/api.md` stays in sync; CI fails on drift.
- **Performance budget** -- DONE: `task profile` (`scripts/profile.lua`,
  luajit interpreter over the compiled `build/`) asserts `route.plan-week`
  under 5 ms median over 100 fixture players spanning all 27 class/spec
  pairs; measured ~1.4 ms median at landing.

## Scope expansion (decided 2026-06-05)

Routina grows from "BiS route planner" to **weekly routine planner**: quest
and attunement chains, badge/gold/rep goal targets, player-authored plans,
and TomTom waypoint integration. Decisions locked with the owner:

- **All of it ships before 1.0.** The release (now Phase 10) moves out; the
  first public impression is the full routine planner, not the BiS slice.
- **Quests:** attunement chains (Attune-style step tracking), BiS-reward
  quests as plan activities, daily circuits as runnable routes, and an
  arbitrary player-defined chain tracker -- all on one chain model.
- **Goals are targets, not modes.** The player states weekly goals ("150
  badges for the belt", "5000g for the epic mount"); the planner builds a
  plan toward the reset deadline and reports P10/P50/P90 progress, exactly
  as it does today for BiS slots. Resolves OQ-6 as a side effect.
- **Gold non-goal lifted partially.** Gold-farm routes and gold goals are in
  scope. AH *economy play* (scanning, flipping, posting) stays out; when TSM
  or Auctionator is installed we may *read* their price data through a
  soft-dep facade, otherwise vendor value + curated estimates only.
- **Data via GPL import**, same playbook as the BiS catalog: vendor a
  GPL-compatible chain/coordinate source (candidate: Attune -- verify its
  exact GPL version against our GPL-2.0 first, OQ-10), generate Fennel data
  modules, keep a hand-authored curator overlay for fixes.
- **Yield numbers (gold/h, badges/h):** curated estimates as the cold-start
  baseline (badges are deterministic: bosses x 1), refined by the player's
  own recorded history -- the same pattern as `bayesian-luck`.

**PRD updates: DONE (2026-06-05)** -- vision §1, non-goals §5, scope
§6.8-6.11, UX §9 (four tabs), and OQ-10..14 promoted into §13 (OQ-10 and
OQ-13-for-chains resolved on promotion).

## Phase 6 -- Quest & chain engine (CODE-COMPLETE, pending in-game smoke)

> All seven steps below are merged and green under `task lint && task test`
> (423 specs; `task profile` median ~1.5 ms, still inside the M5 budget).
> Flips to DONE after the live smoke in the exit criteria (turn in a tracked
> quest -> chain advances, plan re-renders, no Lua errors) passes on a TBC
> Anniversary client.

Goal: chains -- attunements first -- are first-class citizens: tracked step
by step from the quest log, surfaced in the weekly plan, and feeding the
`requirements` gates that today are static booleans.

Order matters; later items depend on earlier.

1. **PRD sync** -- apply the scope-expansion edits listed above; move OQ-10..14
   into PRD §13.
2. **Schemas -- `src/domain/schemas.fnl`** (schema change; owner-approved
   2026-06-05). `ChainDef` (id, name, kind `:attunement | :quest-line |
   :daily-circuit | :custom`, steps), `ChainStep` (quest-id(s), step type
   `:quest | :kill | :item | :dungeon`, optional coord `{:map :x :y}`,
   prerequisite), `ChainProgress` (per-character current step, completed
   set). Coordinates enter the domain model here; Phase 9 consumes them.
3. **Data import -- `scripts/import-chains.lua`** (`task import-chains`).
   Vendor the chain source (OQ-10 license check first), generate
   `src/domain/chains/data.fnl` -- TBC attunement chains (Karazhan key,
   SSC, TK, ...) with quest IDs and step coords. Curator overlay stays
   available for corrections, per the BiS playbook.
4. **`src/domain/chains.fnl`** -- pure: `next-step`, `progress`,
   `chain-complete?`, `steps-remaining`, `est-minutes-remaining`. Operates
   identically on imported and player-authored (`:custom`, Phase 8) chains.
5. **Quest log events -- `src/core/events.fnl` + `src/core/wow.fnl`.**
   `QUEST_TURNED_IN` / `QUEST_LOG_UPDATE` advance `ChainProgress`; seed from
   the completed-quests query on login. **Verify every API signature against
   warcraft.wiki.gg for the TBC 2.5.x client -- never invent.** Persisted at
   `db.char.chains` with a `db.version` bump + migration.
6. **Chains feed the planner.**
   - Quests whose reward is in the BiS catalog become `:quest` ActivityDefs
     (drop-table already models quest sources at p=1.0).
   - The *next step* of an active attunement chain appears as a plan step
     ("do the next Kara key step, ~25 min") scored by what it unlocks.
   - `requirements-met?` attunement gates become *derived* from chain
     progress instead of manual options toggles (manual override retained
     for alts attuned before install).
7. **UI.** A fourth **Chains** tab (OQ-13 resolved 2026-06-05; PRD §9 is now
   "one panel, four tabs"): per-chain progress + next-step rows; the weekly
   plan carries a next-step advisory; why-drawer explains what an attunement
   unlocks.

Exit criteria:

- Fixture chain advances deterministically in busted from a synthetic quest
  log; no WoW API in `src/domain/chains.fnl`.
- Attunement gate flips from chain progress (fixture), manual override still
  wins when set.
- Live smoke: turning in a tracked quest advances the chain and re-renders
  the plan with no Lua error.
- Domain coverage >= 85% holds; `/docgen` regenerated.

Open questions this phase introduced (both **resolved 2026-06-05**, full
text in [PRD §13](PRD.md#13-open-questions)):

- ~~**OQ-10 -- chain data source & license.**~~ **RESOLVED:** vendored from
  the Attune addon (author Cixi) at a pinned SHA. Attune is **unlicensed**;
  the owner accepted the risk explicitly and Routina relicensed to
  **GPL-3.0** (see `CREDITS.md`). Attune data has no coordinates --
  chain-step waypoints come from a separate source in Phase 9.
- ~~**OQ-13 -- surface for chains & goals.**~~ **RESOLVED for chains:** a
  fourth **Chains** tab (PRD §9 updated to "one panel, four tabs"); the
  weekly plan carries only a next-step advisory. Goals placement stays open
  for Phase 7 §6.

## Phase 7 -- Goal targets & multi-currency engine (CODE-COMPLETE, pending in-game smoke; resolves OQ-6)

> All six steps below are merged and green under `task lint && task test`
> (507 specs; `task profile` median ~1.45 ms, inside the M5 budget). Flips to
> DONE after the live smoke in the exit criteria (add a goal in options ->
> the Plan tab grows a goals card and reorders; a tracked heroic visit
> records its take with the toggle on) passes on a TBC Anniversary client.

Goal: the player states weekly goals; the planner builds toward them with
the same honest P10/P50/P90 it gives BiS slots today. Badges and gold become
first-class yields next to drop probabilities.

1. **Yield model** -- DONE. `schemas.ActivityYield` + generated
   `src/domain/yields/data.fnl` (`task import-yields`: curated gold bands +
   badge counts from `scripts/yields-curated.lua`, boss rosters derived from
   the nexus dataset); `src/domain/yields.fnl` exposes lookups and
   `blended-band` (n/(n+5) shrinkage toward recorded history). Badges are
   deterministic per clear (heroic boss x 1; raids 0 until Anniversary badge
   rules are live-confirmed -- curated override ready). Gold is an honest
   `{:gold-min :gold-max}` band (OQ-12 resolved 2026-06-05).
2. **`src/domain/goals.fnl`** -- DONE. Pure: `GoalDef` validation
   (normalize/to-db), progress from plan-time holdings (money, badge count,
   owned items, standing, chain fraction -- never week-scoped accounting),
   deadline-aware urgency (OQ-11 resolved 2026-06-05: urgency = min(1,
   deficit/achievable-before-reset), daily runs shrink to the days left),
   and `project` -- per-goal P10/P50/P90 (badges arithmetic, gold seeded-MC
   uniform inside the band, items at-least-one, rep/chain flat -- honest).
3. **Route scoring** -- DONE. `RouteContext` gains
   `:goals/:goal-progress/:gold-bands/:reset-at`; goal-paying activities
   stay candidates even with no BiS left; the scorer adds the goal term (the
   densest source earns the full urgency, others their share; zero with no
   goals, so goal-free plans are byte-identical). `goals.project` carries
   the "P50: 130 of your 150 badges" band into the Plan tab.
4. **History extension** -- DONE. `History` gains per-activity `:yields`
   (runs / gold / badges); the dispatcher tracks instance VISITS (wiki-
   verified PLAYER_MONEY money deltas + Badge of Justice 29434 self-loots,
   attributed via GetInstanceInfo -> `ctx.activity-for-instance`, heroic =
   difficultyID 2) behind an off-by-default "Track yields" toggle, the same
   family as luck tracking. db.version 2 -> 3 with migration.
5. **Price facade -- `src/core/prices.fnl`** -- DONE. Read-only, headless-
   safe, resolved at call time behind pcall: TSM dbmarket > Auctionator last
   scan > GetItemInfo vendor price; `.toc` declares the OptionalDeps. No
   scanning, no posting -- AH play stays a non-goal.
6. **UI** -- DONE. OQ-13-for-goals resolved 2026-06-05: per-goal progress
   cards render at the HEAD of the Plan tab (above the chain advisory); the
   goal editor is a fifth "Goals" options sub-panel (add/remove, validated
   before persisting; pure builders in `src/ui/options-goals.fnl`). The Plan
   tab's pure view-models moved to `src/ui/tabs/weekly-vm.fnl`.

Exit criteria:

- For a fixture player with a 150-badge goal, the plan surfaces
  badge-dense heroics and the projection reports a deterministic badge count
  per planned run -- busted, seeded, no WoW API. **(busted-green)**
- Adding a gold goal visibly reorders the plan toward high-gold/h
  activities; removing it restores the BiS-first order. **(busted-green)**
- Addon loads and prices fall back cleanly with neither TSM nor Auctionator
  installed. **(busted-green; live smoke pending)**

Open questions this phase introduced (both **resolved 2026-06-05**, full
text in [PRD §13](PRD.md#13-open-questions)):

- ~~**OQ-11 -- multi-goal arbitration.**~~ **RESOLVED: deadline-aware.**
  Urgency grows as the reset nears relative to what is still achievable;
  goals sum; no options knob.
- ~~**OQ-12 -- gold/h estimate provenance.**~~ **RESOLVED: honest band.**
  Curated `{min, max}` per clear, scored at the midpoint, projected
  uniformly, rendered as a range, tightened by the player's own recorded
  visits.

## Phase 8 -- Player-authored plans

Goal: the player can add what the catalog doesn't know, and edit what the
planner proposes -- without breaking determinism or the pure core.

1. **Custom activities.** Authored in UI: name, est-minutes, reset
   (`:weekly | :daily | :none`), optional yields and goal link. Stored in
   `db.profile.custom-activities`, validated against `schemas.ActivityDef`
   at the boundary, competing in scoring as equals. `db.version` bump +
   migration.
2. **Plan edits -- pin / skip / reorder.** Persisted per character;
   expressed as *constraints* in `RouteContext` (pins ordered first, skips
   excluded) so `route.plan-week` stays pure and deterministic given the
   same constraints.
3. **Route constructor.** A plan as an ordered checklist of steps; steps
   optionally carry coords (consumed by Phase 9 circuits). Custom chains
   reuse the Phase 6 `ChainDef :custom` model -- one mechanism, two authors
   (importer / player).
4. **UI.** "Add activity" flow, card context actions (pin / skip / move),
   constructor editor with step checklist. All AceGUI via the facade.

Exit criteria:

- A fixture custom activity with a strong yield outranks a weak catalog one
  -- busted, no WoW API.
- Pin/skip constraints round-trip SavedVariables and survive `/reload`
  (smoke); plan respects them deterministically (busted).
- A custom chain advances through the constructor checklist identically to
  an imported chain (shared spec).

## Phase 9 -- Waypoints & TomTom

Goal: every plan step can point somewhere; farm and daily circuits guide the
player around a loop. First external soft-dependency -- the addon must stay
fully functional, error-free, and quiet without TomTom installed.

1. **Coordinate consolidation.** `{:map :x :y}` entered the schemas with
   Phase 6 chain steps; extend to ActivityDef (instance entrance,
   questgiver) and constructor route steps. Entrance coords are a small
   curated set; chain step coords come from the Phase 6 import.
2. **`src/core/tomtom.fnl` facade** -- headless-safe (guard on `_G.TomTom`,
   no-op when absent), the only module allowed to touch the TomTom API.
   **Verify every TomTom API call against the TomTom source -- never
   invent.** `.toc` gains `## OptionalDeps: TomTom` (+ TSM/Auctionator from
   Phase 7); update `.pkgmeta` accordingly.
3. **Waypoint per plan step.** A click target on each plan card -> one
   waypoint (entrance / questgiver / current chain step). The minimal,
   highest-value integration -- lands first.
4. **Circuit guidance.** Daily circuits and farm routes as ordered waypoint
   loops: arrival advances to the next point (TomTom arrival callback --
   mechanics are OQ-14), looping for repeatable farm laps.
5. **Chain step waypoints.** The Phase 6 "next step" row and the why-drawer
   gain a "point me there" action using imported step coords.

Exit criteria:

- With TomTom absent: zero Lua errors, waypoint affordances hidden or
  disabled -- verified by a busted-level facade test plus live smoke.
- With TomTom present: clicking a plan card sets the arrow; a fixture daily
  circuit advances through its loop on simulated arrivals.
- No coordinate literals outside generated data and the curated entrance
  table.

New open question (now in [PRD §13](PRD.md#13-open-questions)):

- **OQ-14 -- circuit auto-advance mechanics.** TomTom's arrival callback API
  vs polling player position (an `OnUpdate` -- needs the written
  justification per UI rules). Resolve by reading the TomTom source before
  building Phase 9 §4. *Affects:* circuit guidance, perf budget.

## Phase 10 -- Release 1.0 (TBC Anniversary Phase 1)

> Renumbered from Phase 6 (2026-06-05): the scope expansion ships first, so
> 1.0 is the full routine planner -- BiS engine, chains, goals, player plans,
> waypoints.

- Full wowUnit smoke suite, manually executed pre-tag.
- BigWigs packager release run, signed against `## Interface: 20505`.
- CurseForge + Wago listings, screenshots, short demo gif.
- User-facing docs: `docs/USER_GUIDE.md` (install, first-run, FAQ).
- Tag `v1.0.0`, write release notes from the milestone.

## Phase 11+ -- Post-1.0 (sketch, **[open]**)

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
- Auction house **economy play**: scanning, flipping, posting, crafting
  margins. (Narrowed 2026-06-05: gold-*farm* routes and gold goals are now
  in scope -- Phase 7 -- and prices may be *read* from TSM/Auctionator via a
  soft-dep facade. The AH itself stays TSM territory.)
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
