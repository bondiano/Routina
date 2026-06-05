# Routina -- Product Requirements

> **Status:** Draft, pre-1.0. Last updated 2026-06-05 (scope expansion:
> chains, goals, player plans, TomTom -- see [ROADMAP](ROADMAP.md)
> "Scope expansion").
> **Owner:** @bondiano.
> Engineering rules live in [ARCHITECTURE](ARCHITECTURE.md),
> [CONVENTIONS](CONVENTIONS.md), [WOW](WOW.md), [TESTING](TESTING.md),
> [TYPES](TYPES.md), [UI](UI.md), [CONTRIBUTING](CONTRIBUTING.md).
> Delivery plan in [ROADMAP](ROADMAP.md).

## 1. Vision

A weekly *routine* planner for **WoW TBC Classic Anniversary** that tells a
player, in one screen, *which content to run this week to hit their goals
before the next phase ships* -- finishing the BiS list first among them, but
also attunement chains, badge targets, gold for the epic mount, and the
plans the player writes themselves.

Not another loot tracker. Not a DPS meter. A **decision support tool** for
the 90 minutes a player can actually log in this week.

## 2. Problem

End-game TBC progression is constrained by **weekly lockouts** and
**BiS-shaped loot tables**. Every player faces the same recurring
questions:

- "I have three hours tonight. Karazhan or two heroics?"
- "How many more SSC clears until my T5 chest is statistically likely?"
- "If my guild brings four casters, is the Maiden trinket still worth my
  lockout?"
- "Which reputation grind unlocks the most BiS slots fastest?"

Today these are answered by external spreadsheets, Discord wisdom, or
gut feel. None of those:

- Know the player's current gear.
- Know the player's remaining lockouts.
- Update as the week progresses.
- Quantify uncertainty -- "you have a 62% chance of finishing your boots
  by reset" rather than "go to ZA, probably".

Routina collapses all of that into a single in-game panel.

## 3. Users

**Primary:** TBC Classic Anniversary players, level 70, raiding casually
(1-2 nights/week) or semi-hardcore (3-4 nights/week), who care enough about
gear optimization to install an addon but do **not** want to maintain a
spreadsheet.

**Secondary:** Officers planning guild signups -- "we have 8 mages, who
benefits most from coming to ZA?".

**Not the target:**

- Players who already run BiSTracker + RaidPlanner + LootCouncil and have
  a stable workflow.
- Players who only PuG and have no consistent weekly schedule.
- Retail WoW players. (Different lockout model, different gearing
  philosophy.)

## 4. Goals

A successful Routina v1.0 lets a player:

- **G1** -- See, in one panel, every weekly activity worth their time *for
  this character* this week, ordered by expected BiS progress.
- **G2** -- For each activity, see the top 3 target items and the
  probability of dropping at least one this week.
- **G3** -- See remaining lockouts with reset timers in the same panel.
- **G4** -- Adjust assumptions (ML competition, slot weights) and watch
  the plan reorder live.
- **G5** -- Trust the probabilities. Same inputs always produce the same
  plan. Monte Carlo projections come with a P10 / P50 / P90 range, not a
  single number.

## 5. Non-goals (v1.0)

- Combat or rotation advice. Routina is a *planner*, not a DPS meter.
- Auction house **economy play**: scanning, flipping, posting, crafting
  margins. (Narrowed 2026-06-05: gold-*farm* routes and gold goals are in
  scope -- §6.9; item prices may be *read* from TSM/Auctionator through an
  optional soft-dep facade when one is installed.)
- Retail WoW support.
- Cloud sync. Everything lives in `SavedVariables`.
- Any AI/LLM call from inside the addon at runtime.
- Multi-character cross-planning. (Re-evaluate post-1.0; see §13.)
- Group composition optimization. (Officers tab is a stretch goal, not
  v1.0.)

## 6. Scope (v1.0 feature list)

### 6.1 Weekly planner panel

Ordered list of recommended activities for the current week. Each row:

- Activity name, type (raid / heroic / daily / weekly quest / rep hub).
- Score (composite of expected BiS slots filled).
- Estimated minutes.
- Top 3 target items, each with `at-least-one(p, planned-runs)`.
- Lockout state if applicable.

Refreshes on relevant WoW events (raid kill, instance reset, gear change).

### 6.2 Lockouts panel

Active raid and heroic lockouts with reset timers. Pulled from
`UPDATE_INSTANCE_INFO` and similar events. Visually surfaces "expires in
< 24h" entries.

### 6.3 BiS panel

Per-slot table for the current character's spec:

- Currently equipped item.
- Target BiS item, source activity.
- `at-least-one(p, N)` over the planner's projected runs.
- Visual gap indicator.

### 6.4 Probability engine

- `at-least-one(p, n)` -- binomial complement.
- `exactly-k(n, k, p)` -- binomial pmf.
- `expected-runs(p)` -- geometric mean.
- `effective-rate(p, competitors)` -- ML competition adjustment.
- `bayesian-luck(drops, runs, base-p)` -- posterior given history.
- `coupon-collector-mc(items, runs, sims, rng)` -- Monte Carlo over the
  week, returns P10/P50/P90.

All pure. All seedable. All testable in busted without WoW.

### 6.5 Options

AceConfig panel:

- Spec override (default: detected from talent tree).
- ML competition assumption: raid composition by role (per-item contention
  derived from the BiS catalog; OQ-3 resolved), with a global fallback
  slider and a per-activity override map.
- Slot weight tuning (1-5).
- Reset behaviour (e.g. "weekly luck reset on Tuesday morning").
- Profile management (AceDBOptions).

### 6.6 Slash commands

- `/routina`, `/rt` -- open / close main panel.
- `/rt plan` -- print weekly plan to chat.
- `/rt reset` -- reset luck history.
- `/rt debug` -- dump diagnostic state to log.

### 6.7 Localization

- `enUS` ships with v1.0.
- `ruRU` post-launch via community translation, behind AceLocale.

### 6.8 Quest & attunement chains (added 2026-06-05; ROADMAP Phase 6)

- Attunement chains (Karazhan key, SSC, TK, ...) tracked step by step from
  the quest log; data imported from the Attune addon dataset.
- A Chains tab shows per-chain progress and the next actionable step; the
  next step of an active attunement surfaces in the weekly plan as an
  advisory.
- Attunement gates in the planner derive from chain progress (manual
  override retained).
- Quests with BiS rewards are plan activities (drop p = 1.0).
- The same chain model carries daily circuits and player-defined chains
  (§6.10).

### 6.9 Goal targets (added 2026-06-05; ROADMAP Phase 7)

- The player states weekly goals -- "150 badges for the belt", "5000g for
  the epic mount", a rep standing, a BiS slot -- and the planner builds
  toward the reset deadline, reporting P10/P50/P90 progress per goal.
- Activity yields: badges (deterministic, bosses x 1), gold (curated
  estimate refined by the player's own recorded history), reputation.
- Resolves OQ-6: heroics rank by contribution to the *active goals*, BiS
  by default.

### 6.10 Player-authored plans (added 2026-06-05; ROADMAP Phase 8)

- Custom activities (name, est-minutes, reset cadence, optional yields)
  competing in scoring as equals.
- Plan edits -- pin / skip / reorder -- persisted as planner constraints.
- A route constructor: ordered step checklists, reusing the chain model.

### 6.11 TomTom waypoints (added 2026-06-05; ROADMAP Phase 9)

- Optional soft-dependency: with TomTom installed, every plan step gets a
  "point me there" waypoint; daily circuits and farm routes guide around a
  loop; chain steps point at their location. Without TomTom: silent no-op,
  zero errors.

## 7. Success metrics

Routina is a single-developer hobby project; metrics stay modest and
truthful.

- **M1 -- Adoption:** >=200 unique installs across CurseForge + Wago in
  the first month after v1.0.
- **M2 -- Trust:** zero "wrong probability" bug reports filed in the first
  month. (One bug -> investigate before next release.)
- **M3 -- Engagement:** >=30% of installs have non-default options after
  two weeks (proxy: someone bothered to tune it).
- **M4 -- Code health:** >=85% coverage on `src/domain/` maintained
  throughout v1.0 development.
- **M5 -- Performance:** `route.plan-week` <5 ms median over 100 fixture
  players on a mid-range laptop.

## 8. Constraints

Hard product constraints (engineering constraints are in [WOW](WOW.md)):

- **Read-only.** Routina never equips, trades, rolls, or messages on
  behalf of the player.
- **No external network calls.** Everything is local.
- **No telemetry.** Routina never phones home.
- **Single-character data ownership.** v1.0 stores per-character data
  only. Account-bound data lands post-1.0 if at all (§13).
- **Phase-aware but phase-faithful.** Routina updates its catalog with
  each TBC Classic Anniversary content phase. It does not predict items
  not yet on live servers.

## 9. UX principles

- **One panel, four tabs.** Weekly, Chains, Lockouts, BiS. Options behind a
  gear icon. No deep menus. (Was three tabs; OQ-13 resolved 2026-06-05 --
  chains earned a tab of their own rather than crowding the Plan stack.
  Goals UI placement re-opens this in Phase 7.)
- **Probabilities are first-class.** Every recommendation shows the
  number behind it. No "trust me" UI.
- **Explainable.** Right-click a recommendation or click "Why?" -> an
  in-panel slide-in drawer shows the top contributing items, weights, and
  lockout decay. No modal popups.
- **Journal, not control panel.** Warm parchment, serif headers, card
  stack instead of a grid. Inspired by Attune and Dialogue UI; explicitly
  not the dense TSM table aesthetic. Feels native to Warcraft without
  mimicking the default Blizzard frame skin. Full visual language in
  [UI](UI.md).
- **Quiet.** No popups, no chat spam, no sounds unless the user opts in.

## 10. Out-of-scope clarifications (FAQ)

- **"Will it auto-pick rolls?"** No. Read-only, §8.
- **"Will it share my plan to chat?"** Only when the user types
  `/rt plan`. Never automatically.
- **"Will it integrate with WeakAuras?"** A post-1.0 hook is on the
  table; not v1.0.
- **"Does it work on Wrath / SoD / Retail?"** No, and we will refuse PRs
  that bend the architecture to make it portable. Different lockout
  models, different scope.

## 11. Dependencies

- **Ace3** suite (AceAddon, AceDB, AceEvent, AceConfig, AceGUI,
  AceLocale, AceDBOptions). Vendored in `Libs/`.
- **LibStub.** Vendored.
- No other runtime dependencies. The Fennel compiler is build-time only.

## 12. Glossary

- **Lockout** -- WoW's per-character timer preventing re-entry into a
  saved instance until reset.
- **BiS** -- Best-in-slot. The item a given spec ideally equips in a
  given gear slot for a given content phase.
- **ML** -- Master Loot. A loot mode where one player distributes drops;
  contrasts with personal loot.
- **Reset** -- Weekly raid reset (Tuesday US, Wednesday EU) and daily
  reset (server midnight in TBC Classic Anniversary).
- **Lockout decay** -- The progressively shrinking value of a lockout as
  the week progresses (a Tuesday clear is worth more than a Monday
  clear).
- **Effective rate** -- The drop rate `p` adjusted for competitors in
  the loot pool: `p / competitors`.
- **Bayesian luck** -- A posterior estimate of "is this player getting
  lucky or unlucky" given observed drop history vs base rate.
- **Phase** -- A TBC Classic Anniversary content release window (Phase 1,
  Phase 2, ...). Each phase ships new raids and adjusts BiS lists.

## 13. Open questions

These are unresolved and need an answer before the relevant
[ROADMAP](ROADMAP.md) phase lands. **`Ask` before changing the answer.**

- ~~**OQ-1 -- Drop table source of truth.** Scrape Wowhead at build time or
  commit a hand-curated JSON?~~ **RESOLVED (2026-06-03):** neither -- drop rates,
  bosses, and source zones are imported by `scripts/import-drops.lua` from the
  **MIT `nexus-devs/wow-classic-items` dataset** (already vendored for item
  names), the same structured-import approach used for the BiS catalog. No
  Wowhead scraping, no `task build` network dependency (the derived
  `vendor/bis-source/item-sources.lua` is committed). See [ROADMAP](ROADMAP.md)
  Phase 2 §4.

- **OQ-2 -- BoE drops in v1.** Do we include Bind-on-Equip drops in
  weekly scoring, given they are often replaceable via the auction
  house? Including them inflates score for activities that drop a lot
  of vendor trash; excluding them under-counts activities that drop
  genuinely useful BoEs (e.g. some Karazhan trinkets).
  *Affects:* Phase 2 / route scoring.

- ~~**OQ-3 -- Loot rules per raid.** Encode ML / SR / GDKP per saved raid,
  or expose a single global "competitors per slot" assumption? Per-raid
  is accurate but laborious to set up; global is fast but lies for
  players raiding with mixed groups.~~ **RESOLVED (2026-06-05): neither --
  competition is modelled by role from a single raid composition.** The player
  declares who they usually raid with ({tank, healer, melee, ranged, caster}
  -> headcount, one options sub-panel); an item's *contending roles* are
  derived from the BiS catalog itself (every role whose class/spec list names
  the item, via `src/domain/competition.fnl`); per-item competitors = the
  contending headcount, scaled to the activity's `:group-size` (10/25/40/5)
  and floored at 1. This is per-item accurate (a caster trinket competes only
  against casters and the odd prot paladin) without per-raid setup. ML / SR /
  GDKP are deliberately **not** encoded -- SR/GDKP re-weight *who* wins, not
  *how many contend*, which is all `effective-rate` consumes. The global
  "competitors per drop" slider and the per-activity override map remain as
  manual escape hatches (precedence: per-activity > uncontested-type exemption
  > composition > global > 1); non-instanced pickups (vendor / quest / daily /
  rep-hub) are always uncontested. See [ROADMAP](ROADMAP.md) Phase 4 §2.

- ~~**OQ-4 -- Reputation grinds in the weekly plan.** Treat reputations
  (Aldor / Scryer / Cenarion Expedition / ...) as weekly activities, or
  hide them in a separate tab?~~ **RESOLVED (2026-06-01):** reputations are
  modelled as weekly activities -- `:rep-hub` is a live `ActivityDef` type and
  `ActivityRequirements` carries an optional `:rep` gate. See
  [ROADMAP](ROADMAP.md) Phase 2 §2. The "score per hour" warp for multi-week
  grinds is deferred to route scoring (Phase 2 §5 / OQ-6).

- **OQ-5 -- Cross-character planning.** Defer past v1.0 (single-character
  only), or design AceDB profiles for cross-char from day one? The
  AceDB shape is hard to retrofit.
  *Affects:* Phase 5 / profiles, and §6 scope.

- ~~**OQ-6 -- Heroic dungeon ranking.** Should heroics be ranked by
  reputation-per-hour, badges-per-hour, or BiS-per-hour?~~ **RESOLVED
  (2026-06-05, shipped with ROADMAP Phase 7):** BiS-per-week by default;
  stating a goal (§6.9) folds that goal's yield into the score
  deadline-aware (OQ-11), so a badge goal surfaces badge-dense heroics and
  removing it restores the BiS-first order. No mode toggle -- goals are
  targets, not modes.

- **OQ-7 -- Lockout decay curve.** Linear ("a clear is 50% as valuable on
  Friday as on Tuesday") or step ("full value until 24h before reset,
  then half")? Affects whether the planner urges last-minute resets.
  *Affects:* Phase 2 / `route`.

- ~~**OQ-10 -- chain data source & license.** Where do attunement chain
  steps (quest IDs, ordering) come from, and is the source license
  compatible?~~ **RESOLVED (2026-06-05):** vendored from the
  [Attune](https://github.com/hippuli/Attune) addon's `AttuneData.lua`
  (author Cixi), via the same pinned-SHA import playbook as the BiS catalog
  (`task vendor-chain-source && task import-chains`). Attune ships **no
  license**; the owner explicitly accepted the redistribution risk, and
  Routina relicensed to **GPL-3.0** the same day (see `CREDITS.md` for both
  risk notes). Quest-step titles are derived from the
  [Questie](https://github.com/Questie/Questie) TBC quest DB (also
  unlicensed, same accepted risk; only factual id → Blizzard-title pairs).
  Attune data carries no coordinates -- chain-step waypoints (§6.11) need a
  separate source, deferred to ROADMAP Phase 9.

- ~~**OQ-11 -- multi-goal arbitration.** Several active goals (§6.9) compete
  for the same hours: priority weights, deadline-aware ordering, or
  proportional coverage?~~ **RESOLVED (2026-06-05): deadline-aware.** Per
  goal, urgency = min(1, deficit / achievable-before-reset); a daily
  activity's remaining runs shrink to the days left before the weekly
  reset, so a goal that is behind schedule pulls its activities up the
  plan and a slack goal barely nudges it. The goal's densest source earns
  the full urgency as score (one default-slot-weight equivalent), other
  sources their proportional share; several goals simply sum. No options
  knob -- the default IS the model (`src/domain/goals.fnl`).

- ~~**OQ-12 -- gold/h estimate provenance.** Curated gold/h varies wildly by
  class, gear, and consumable prices. One conservative number, per-armor
  class, or a wide band rendered honestly as a range?~~ **RESOLVED
  (2026-06-05): an honest band.** Yields carry `{:gold-min :gold-max}` per
  clear (scripts/yields-curated.lua), scoring uses the midpoint, the
  projection samples uniformly inside the band, and the UI renders ranges
  -- never a point estimate. The band tightens toward the player's own
  recorded visits (`yields.blended-band`, n/(n+5) shrinkage), the same
  pattern as the Bayesian luck score.

- ~~**OQ-13 -- surface for chains & goals.** §9 said "one panel, three
  tabs"; chains and goals both want UI.~~ **RESOLVED for chains
  (2026-06-05):** a fourth **Chains** tab (§9 updated); the weekly plan
  carries only a next-step advisory. **RESOLVED for goals (2026-06-05):
  inside the Plan tab** -- per-goal progress cards (P10/P50/P90 band) render
  at the head of the weekly plan, above the chain advisory; the goal
  *editor* is a Goals options sub-panel. The tab count stays at four.

- ~~**OQ-14 -- circuit auto-advance mechanics.**~~ **RESOLVED (2026-06-06):
  TomTom arrival callbacks.** Verified against the TomTom source (Nevcairiel
  mirror of the CurseForge addon): `AddWaypoint` accepts an
  `opts.callbacks.distance[yards] = fn` table that fires as the player
  crosses that range, so `src/core/circuit.fnl` advances the loop inside
  TomTom's own distance watch -- no `OnUpdate` polling, no perf-budget cost,
  no new exception to the UI rules. Resolution lives in ROADMAP Phase 9 §4.

Move an item out of §13 when it has a committed answer. Add new ones
liberally -- this section is meant to grow before it shrinks.

## 14. References

- TBC Classic loot tables and drop rates: Wowhead Classic database.
- Lockout mechanics: https://warcraft.wiki.gg/wiki/Instance#Lockout.
- Beta distribution / Bayesian inference primer:
  https://en.wikipedia.org/wiki/Beta_distribution.
- Coupon collector problem:
  https://en.wikipedia.org/wiki/Coupon_collector%27s_problem.
