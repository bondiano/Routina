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

## Status snapshot (2026-05-28)

| Area | State |
|---|---|
| Build pipeline (`task build/test/lint/package`) | Working |
| Fennel compiler vendored | `vendor/fennel.lua` pinned |
| Domain module: `drop-chance` | Shipped, used as canonical example |
| Tests: busted + Fennel searcher | Wired, 1 spec |
| WoW API mocks | Stub harness in `spec/mocks/wow-api.fnl` |
| Ace3 wiring | **Not yet** -- `src/core/main.fnl` is a placeholder slash-cmd |
| Event dispatcher | **Not yet** |
| SavedVariables / AceDB | **Not yet** (`RoutinaDB` declared in `.toc` only) |
| UI shell (custom CreateFrame, journal theme) | **Not yet** -- see [UI](UI.md) |
| BiS catalog | **Not yet** |
| Lockout / activity model | **Not yet** |
| Routing engine | **Not yet** |
| Localization scaffold (`Locales/`) | Empty |
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

## Phase 1 -- Foundation (NEXT)

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

## Phase 2 -- Domain MVP

Goal: enough pure modules to *describe* a weekly plan, even if the UI is
ugly.

1. **`src/domain/lockouts.fnl`**
   - Pure model of raid/dungeon lockouts: id, expiry timestamp, bosses
     killed/remaining, owner key.
   - Predicates: `lockout-active?`, `lockout-shareable?`, `time-until-reset`.
   - Fed by `src/core/events.fnl` via `UPDATE_INSTANCE_INFO`,
     `RAID_INSTANCE_WELCOME`, `RAID_BOSS_KILLED`.
2. **`src/domain/activities.fnl`**
   - Registry of weekly content: raids, heroic dungeons, dailies, PvP weekly,
     reputation hubs.
   - Each activity has `:id`, `:type`, `:reset` (`:weekly | :daily | :none`),
     `:length-estimate`, `:requirements`.
3. **`src/domain/bis-catalog.fnl`** + **`src/domain/bis/<class>/<spec>.fnl`**
   - Static catalog of BiS sets per class/spec/phase, generated via the
     `bis-catalog` macro from `.claude/examples/05-bis-catalog-macro.fnl`.
   - Curator workflow: `bis-curator` agent updates these files.
4. **`src/domain/drop-table.fnl`**
   - Map `{:item-id -> {:source-activity :base-drop-p :ml-pool}}`.
   - Seeded from Wowhead exports; manual review before commit.
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

1. **Bayesian luck score** -- already drafted in `drop-chance.bayesian-luck`.
   Wire `observed-drops` / `observed-runs` from SavedVariables history.
2. **ML competition modelling** -- per-activity `competitors-by-role` map,
   exposed in options. `effective-rate` flows through `route` scoring.
3. **Monte Carlo route projection** -- `coupon-collector-mc` over the planned
   week with a user-controlled seed; UI reports P10/P50/P90 of "slots filled
   by reset".
4. **Recommendation diff** -- explain why activity A out-scores B for *this*
   player (top-3 contributing items, slot weights, lockout decay).

Exit criteria:

- Adjusting "competitors on caster trinket" in options visibly reorders the
  weekly plan.
- Monte Carlo runs in <50 ms for a realistic week on a mid-range laptop.

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
