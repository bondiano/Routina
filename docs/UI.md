# UI

> **MIGRATION (current):** the main panel was moved off the bespoke
> parchment/`CreateFrame` stack onto **AceGUI-3.0 + SFX-Widgets**. The single
> stretched parchment bitmap could not be themed at arbitrary frame sizes
> (see the retired `frames.fnl` war-diary), so AceGUI now owns layout and
> backdrop; we tint it toward parchment with theme tokens. Sections below that
> describe custom `CreateFrame` widgets, frame pools, `dom.render!`, and the
> slide-in why-drawer are **historical** — see §2 for the current model. The
> *aesthetic intent* (warm, journal-like, not TSM-dense) still guides token
> choices; the *mechanism* changed.
>
> The Routina panel is a **weekly journal**, not a control panel. Tone is set
> by Attune and Dialogue UI: warm parchment, serif headers, soft motion,
> one decision at a time. Anti-reference: TSM grid density.
>
> Pairs with [PRD §9](PRD.md#9-ux-principles) (UX principles),
> [ARCHITECTURE](ARCHITECTURE.md) (layering), [WOW](WOW.md) (frame perf),
> [CONVENTIONS](CONVENTIONS.md) (Fennel style).

## 1. Aesthetic -- "журнал на эту неделю"

The panel reads as a personal weekly journal a player flips open between
pulls. The visual choices follow from that metaphor:

- **Parchment, not panel.** Backdrop is a warm ecru gradient with a thin
  serif rule under each section. No hard 1px gray Blizzard borders.
- **Serif headers, narrow body.** Titles in Friz Quadrata (`FRIZQT__.TTF`),
  body in Arial Narrow (`ARIALN.TTF`). Both ship with WoW; no `LibSharedMedia`
  fonts shipped.
- **Gold accents, ink contrast.** Active tab pill, focused row, "Why?"
  disclosure -- all the same warm gold. Body text is dark ink, never pure
  black.
- **One decision per scroll.** Vertical card stack. The eye lands on the
  top recommendation; everything else is one motion away.
- **Quiet motion.** Fade/slide <=200 ms. No bounce, no glow except a single
  pulse for `<24h` lockouts. No sound, ever.

The visual identity is intentionally distinct from Blizzard's default
panel skin and from TSM-style dense tables. PRD §9 calls for "native
theming" -- read this as *feels native to Warcraft*, not *mimics the default
Blizzard frame backdrop*. Dialogue UI and Attune both clear that bar.

## 2. Frame strategy -- AceGUI-3.0 (current model)

The primary panel is built with **AceGUI-3.0**, resolved through the
`src/ui/acegui.fnl` facade. AceGUI also still backs the **Options** panel
(`src/ui/options.fnl`, via AceConfigDialog).

Why we moved off custom `CreateFrame`:

- The bespoke parchment backdrop was a single stretched bitmap that could not
  be made to read well at arbitrary panel sizes — every resize re-broke the
  painted edges, and the only knobs were pixel `SetTexCoord`/overhang hacks
  tunable solely by eye in-game. AceGUI owns layout + backdrop, so that whole
  class of pixel-tuning disappears.
- AceGUI handles widget pooling, scroll, and tab switching for us.

The trade we accepted: AceGUI carries Blizzard's standard grey skin (SFX-Widgets
does **not** reskin it). We nudge it toward the journal warmth with theme tokens
— `acegui.tint-frame!` for the Frame backdrop and `acegui.themed-label!` for
label colour/font — rather than a bespoke parchment texture.

Current structure:

- **Root** = `AceGUI:Create("Frame")` (tinted) with `SetTitle` (char · class)
  + `SetStatusText` (reset window) + a `TabGroup` of three tabs.
- **TabGroup** fires `OnGroupSelected`; the handler does
  `container:ReleaseChildren()` then asks the tab module to repaint.
- **Tab modules** export a single `render! [container]` (idempotent populate).
  The Plan tab adds a `ScrollFrame` of `InlineGroup` cards built from the pure
  `card-view-model`.
- **why-drawer** is a singleton `AceGUI:Create("Frame")` that pops to the right
  of the panel and lists the score breakdown as `SFX-Info` rows.

Hard rules:

- **Never invent AceGUI API.** Verify against the vendored source in
  `Libs/Ace3/AceGUI-3.0/`. Registered layouts are only `List`/`Fill`/`Flow`/`Table`.
- **Go through the facade.** `src/ui/acegui.fnl` is the one place that resolves
  AceGUI via LibStub; it degrades every helper to a no-op when the lib is absent
  (busted), mirroring how `options.fnl` guards AceConfig.
- **SFX-Widgets is optional.** Always branch on `acegui.registered?` and fall
  back to a built-in widget (`Label`/`Heading`).

## 3. Information architecture

```
+--------------------------------------------------------------+
|  Bondiano  ·  Shadow Priest         Week 47  ·  resets 2d 4h |
|  -------------------------------------------------------  ⚙  |
|  ( Plan )    ( Lockouts  3 )    ( BiS  62% )                 |
|                                                              |
|  [ tab content -- scrollable card stack ]                    |
|                                                              |
+--------------------------------------------------------------+
```

- **Header strip** -- character name + spec on the left, current reset
  window in the middle, gear icon on the right. Reads like a journal
  spine.
- **Tab pills** -- three pills, not Blizzard tabs. Inactive pills are
  ink-on-parchment; the active pill is gold-on-ink. Pills carry badge
  counts: `Lockouts 3`, `BiS 62%`. The badge is the Attune touch -- you
  know the state before you click.
- **Gear icon** -- opens AceConfig Options. Stays native there.

Slash commands open / close the root frame (`/routina`, `/rt`); the rest
of the slash surface (`/rt plan`, `/rt reset`, `/rt debug`) is documented
in [PRD §6.6](PRD.md#66-slash-commands).

## 4. Theme tokens

Theme is plain data, lives in `src/ui/theme.fnl`, and is the only place
colours, fonts, and spacing literals appear. Widgets read tokens; they
do not hardcode hex.

```fennel
;; src/ui/theme.fnl (sketch)
{:palette {:parchment   "ECDDB6"
           :parchment-2 "DCC89C"
           :ink         "2A1F14"
           :ink-faint   "5A4830"
           :gold        "C9A24A"
           :gold-bright "F0CC6E"
           :warn        "A93F2D"
           :ok          "5C7A4A"
           :shadow      "00000060"}
 :fonts {:title "Fonts\\FRIZQT__.TTF"
         :body  "Fonts\\ARIALN.TTF"}
 :sizes {:title 18 :section 14 :body 12 :caption 10}
 :spacing {:gutter 12 :inset 16 :rhythm 8}
 :radius {:card 4 :pill 12}
 :motion {:fade-ms 160 :slide-ms 200}}
```

Tokens are pure data; `theme.fnl` has no `CreateFrame` calls and no WoW
globals. It is testable in busted.

**Light/dark variants (Phase 5).** The palette ships in two modes over the
SAME token keys -- `theme.palettes.dark` (the default look above) and
`theme.palettes.light` (light parchment paper, dark ink, accents darkened
for contrast). `theme.set-mode!` swaps which table `theme.palette` points
at; consumers keep reading the same token names and pick the active values
up on their next paint. The switch lives in Options -> General -> Theme
(persisted at `db.char.preferences.route.theme`); applying it is one
ordinary `root.refresh!` -- `acegui.tint-frame!` re-tints idempotently, the
why-drawer re-tints per open, and the pooled meters/timers re-read the
palette in `set!`/`start!`. Both palettes keep §11's colour-blind
invariants (identity reads without hue; the chance-meter gradient stays
saturation-driven).

## 5. Frame discipline

> **Historical (pre-AceGUI).** Bespoke frame pools and `acquire!`/`release!`
> are retired — AceGUI pools its own widgets; repaint is
> `ReleaseChildren()` + rebuild (§2). The remaining live rule is "no
> unjustified `OnUpdate`".

Every widget below obeys these rules. Reviewers reject widgets that don't.

- **Pool, don't allocate.** A widget exports `acquire!` and `release!`.
  Refreshing a card stack returns N frames to the pool and acquires M new
  ones; it never calls `CreateFrame` per refresh.
- **No `OnUpdate` in card bodies.** The only `OnUpdate`-driven widgets are
  `lockout-timer` (throttled to 1.0 s) and `why-drawer` slide animation
  (200 ms, self-disabling).
- **Layout by anchor, not coord.** `SetPoint` against parent insets. No
  `SetPoint("TOPLEFT", UIParent, "TOPLEFT", 387, -212)`.
- **Frames stay in `src/ui/`.** Domain and core never see Frame objects.
  Widgets receive plain data tables and emit plain events.
- **Refresh is debounced.** Plan re-renders coalesce at 100 ms after the
  triggering event.

## 6. Widget catalog -- v1.0

> **Historical (pre-AceGUI).** The custom `activity-card` / `item-pill` /
> `chance-meter` / `bis-slot-row` widgets below were replaced by AceGUI
> `InlineGroup` cards + `InteractiveLabel` rows + `SFX-Info` (§2). The
> proportional `chance-meter` bar is the one piece deferred for a future small
> custom widget; chance currently shows as text + item-quality colour. Kept here
> for the design intent (what each row should communicate).

Six widgets ship with v1.0. Each has its own module under
`src/ui/widgets/<name>.fnl` and follows the pattern in
[.claude/examples/08-ui-widget.fnl](../.claude/examples/08-ui-widget.fnl).

### 6.1 `activity-card`

The atom of the Plan tab.

- **Purpose:** one recommended activity for the week.
- **Inputs:** `{:id :name :type :est-minutes :score :targets [{...}] :why}`.
- **Layout:**
  ```
  [icon]  Karazhan                    ~95 min    ⋮
          Raid · 10-man              [score bar]

          [pill] T4 Shoulders   62% / 3 runs
          [pill] Ring of a 1k Marks 28% / 1 run
          [pill] Aran's Staff   18% / 1 run

          [ Why is this #1? ]
  ```
- **Behavior:** click `Why?` -> `why-drawer:open!(card)`. Right-click is
  reserved for the same explainer (PRD §9). No double-click semantics.
- **Performance:** ~7 child regions (icon, title, type line, score bar,
  three item pills, footer button). Pooled by tab.

### 6.2 `item-pill`

Reused inside `activity-card` and `bis-slot-row`.

- **Purpose:** one BiS target item with its probability for the planned
  runs.
- **Inputs:** `{:item-id :name :quality :p :runs :ml-adjusted?}`.
- **Layout:** square item icon (24x24) + name in quality colour + small
  `chance-meter` + `"<p>% / <n> runs"`.
- **Tooltip:** `GameTooltip:SetItemByID(item-id)`, skinned to parchment.
- **Behavior:** clicking nothing. Hover shows tooltip. Right-click shows
  Wowhead URL in a tooltip footer (never spams chat).
- **Performance:** flyweight -- pillar of every card. Pool size 96 covers
  worst-case (8 cards * 3 targets * 4 lookahead).

### 6.3 `chance-meter`

Atomic visualization for a single probability.

- **Purpose:** show one `p in [0, 1]` as a thin horizontal rune-bar.
- **Inputs:** `{:p :hint?}` where `hint?` is an optional `"P50"` /
  `"per run"` label.
- **Layout:** 80x6 px bar with 25/50/75 percentile tick marks. Fill is a
  warm-to-cool gradient driven by `p`, **not a green/red traffic light** --
  the metaphor is confidence, not pass/fail.
- **Behavior:** static. No animation on first paint. On data change, the
  fill tweens for `motion.fade-ms`.
- **Performance:** 2 textures (track + fill) + 3 tick textures. ~5 frames
  per card body, all pooled.

### 6.4 `lockout-timer`

- **Purpose:** show `time until reset` for one saved instance, with
  urgency.
- **Inputs:** `{:label :reset-at-server-time}`.
- **Layout:** `[label][HHh MMm]` in serif, with a thin urgency bar below
  it. The bar fills as the lockout approaches reset; colour shifts from
  ink-faint -> gold -> warn over the last 24h. A single gold pulse fires
  when crossing 24h. No sound, no flash.
- **Behavior:** `OnUpdate` throttled to 1.0 s (a planner ticking at 60 Hz
  is wasteful and visible in profilers). On `<60s`, throttle drops to
  0.25 s for a smoother last-minute countdown.
- **Performance:** the only `OnUpdate` widget in the card body. Strict
  throttle.

### 6.5 `bis-slot-row`

The atom of the BiS tab.

- **Purpose:** one slot, equipped item -> target item, with the planned
  probability.
- **Inputs:** `{:slot :equipped :target :p :runs :source-activity}`.
- **Layout:**
  ```
  [icon] Head   Cowl of Defiance (148)
                -> Cowl of Beckoning (160)   [meter] 62% / 3 runs
                Source: Karazhan
  ```
- **Behavior:** click row to expand source breakdown (which boss, drop
  rate, ML pool) inline. Expand state is per-row, not persisted across
  reloads.
- **Performance:** rows are pooled and grouped by source activity in the
  view -- the player sees `Karazhan: 3 / 6 slots` headers, not a flat
  spec table. Group headers are pooled separately (~12 max).

### 6.6 `why-drawer`

The killer widget. Replaces the modal "Why is this here?" with an
in-panel slide-in.

- **Purpose:** explain a recommendation without blocking the rest of the
  UI.
- **Inputs:** `{:title :score-breakdown [{...}] :weight-explanation
  :lockout-decay-note?}`.
- **Layout:** slides in from the right half of the root frame, parchment
  background, ink text, gold separators. Contains:
  - Top contributing items with their slot weights.
  - ML competition adjustment (if any).
  - Lockout decay note (if any).
  - A small `Close` button (the only non-card button in the surface).
- **Behavior:** opens with a 200 ms slide-in tween. Closes on `Esc`,
  outside-click, or the close button. Only one drawer instance lives at
  a time; opening another replaces it without re-allocating.
- **Performance:** singleton frame, not pooled. Built once, repopulated
  per open. The slide-in is the only animation that runs to completion
  on every interaction.

## 7. Tabs

Each tab consumes data from `core` and renders a stack of the widgets
above. Tab modules own no frames of their own beyond the tab container;
all visible frames come from a widget pool.

| Tab | Widgets used | Notes |
|---|---|---|
| `weekly` | `activity-card`, `item-pill`, `chance-meter`, `why-drawer` | Sorted by score desc. Summary row at the tail. |
| `lockouts` | `lockout-timer`, optional mini `activity-card` body | Sorted by urgency (lowest `time-until-reset` first). |
| `bis` | `bis-slot-row`, `item-pill`, `chance-meter`, `progress-arc` (header only) | Grouped by source activity, not slot type. |

Tab switch budget: <=16 ms (one frame at 60 Hz). Achieved by reusing the
tab container and only swapping the child stack.

## 8. Tooltips

We do **not** ship our own tooltip frame. `GameTooltip` is reused, with a
custom backdrop applied while a Routina widget owns it and restored on
`OnTooltipCleared`. The backdrop swap touches:

- Backdrop texture (parchment).
- Text colour for headers (ink, not white).
- Border (1 px gold, not Blizzard's default highlight).

Anchor is always `ANCHOR_RIGHT` from the originating widget. Tooltips
that would clip the screen flip to `ANCHOR_LEFT` automatically -- we use
`GameTooltip:SetClampedToScreen(true)`.

Tooltip content stays Blizzard-native:
`GameTooltip:SetItemByID(itemId)` -- we do not synthesise item text.

## 9. Slash command output

`/rt plan` prints to the default chat frame with a `[Routina]` prefix in
gold (`|cffC9A24A`). No custom chat frame, no spam. The chat output
mirrors the Plan tab as plain text, one line per top recommendation:

```
[Routina] Plan for week 47 (resets in 2d 4h)
[Routina]  1. Karazhan       ~95 min  score 0.83  (T4 Shoulders 62%)
[Routina]  2. Heroic Mech    ~35 min  score 0.41  (Gauntlets 22%)
[Routina]  3. SSC            120 min  score 0.36  (T5 Helm 18%)
```

This is the only outbound write Routina ever makes. It is never
automatic -- §10 of the PRD covers that.

## 10. Performance budget

| Operation | Budget |
|---|---|
| Tab switch | <=16 ms |
| Plan re-render | <=50 ms total, debounced 100 ms |
| `chance-meter` data update | <=2 ms |
| `lockout-timer` tick (idle) | <=0.2 ms, 1 Hz |
| `lockout-timer` tick (<60 s) | <=0.4 ms, 4 Hz |
| `why-drawer` open | <=200 ms wall-clock incl. tween |

Frame pool sizes that cover the worst-case TBC Phase 1 week:

- 32 `activity-card`
- 16 `lockout-timer`
- 24 `bis-slot-row`
- 96 `item-pill`
- 128 `chance-meter`

Pools grow on demand but never shrink; addons that thrash pools cost
more in GC than they save in memory.

## 11. Accessibility

- **Font scale.** `theme.sizes` scales by a single multiplier exposed in
  Options (`1.0 / 1.2 / 1.5`).
- **Colour-blind safe.** The parchment + gold + ink trio reads without
  hue. The `chance-meter` gradient is warm-to-cool (saturation-driven),
  not red-to-green.
- **Text-redundant probabilities.** Every `chance-meter` is paired with
  `"<p>%"` text. The meter is supplementary, not the only carrier of
  the number.
- **Keyboard.** `Esc` closes the root frame and any open `why-drawer`.
  Tab pills are clickable; tab key navigation is not in v1.0.

## 12. Testing

UI widgets cannot run under busted -- they need `CreateFrame`. Routina's
approach:

- **Pure parts in busted.** `theme.fnl`, `format.fnl`, anything that maps
  data -> view-model lives in a pure helper next to the widget and is
  unit-tested.
- **Widget shell stubbed.** `spec/mocks/wow-api.fnl` provides a fake
  `CreateFrame` that records calls; we assert structure ("activity-card
  acquired 3 item-pills"), not pixel output.
- **wowUnit covers the rest.** Open every tab, click the gear, open and
  close `why-drawer`, swap a tab while a drawer is open. See
  [TESTING](TESTING.md#tier-2--wowunit-manual-pre-release).

A new widget ships with: a pure view-model spec in busted **and** a line
on the wowUnit smoke checklist.

## 13. Anti-patterns

Reviewers reject:

- `CreateFrame` inside a per-refresh loop. Use a pool.
- A widget that calls a WoW API directly other than `CreateFrame` and the
  frame methods. Data comes from `core`; lookups go through `src/core/wow.fnl`.
- Hex colours or numeric font sizes in a widget file. Read from
  `theme.fnl`.
- `OnUpdate` on anything other than `lockout-timer` and `why-drawer`.
- Tooltip text synthesised in Fennel ("Item: " .. name .. " -- " .. ...).
  Use `SetItemByID`.
- Modal dialogs. The why-drawer pattern replaces them; nothing else needs
  modality.
- Sounds, popups, screen flashes, chat spam.

## 14. Out of scope for v1.0

- Drag-and-drop reordering of the plan. Would mutate UI state in a way
  that breaks "same input -> same plan" (PRD G5).
- Multi-panel layout (detach BiS into a second window). Single panel,
  one focus.
- Live theme editing in Options (custom colour pickers). `theme.fnl` is
  canonical until a player reports it doesn't read. The §4 light/dark
  SELECT shipped with Phase 5 and is not this -- it switches between the
  two curated palettes, it does not edit them.
- Animations beyond fade/slide. No `bounce`, `glow`, `shake`.
- Minimap icon customization beyond the addon's default LibDBIcon
  entry.

Re-open these post-1.0 if there is real user evidence they matter.

## 15. Declarative renderer

> **Retired.** `src/ui/dom.fnl` (the Hiccup renderer) and `src/ui/frames.fnl`
> (parchment backdrop) were deleted in the AceGUI migration (§2). AceGUI is the
> layout engine now; this section is kept only as a record of the prior design.

Static frame trees are expressed as Hiccup-style vectors and fed to
`dom.render!`. State, event handlers, frame pools, and `OnUpdate`-driven
widgets stay imperative. The split echoes §6's "pure view-model + Set!"
rule and the canonical example at
[.claude/examples/09-declarative-ui.fnl](../.claude/examples/09-declarative-ui.fnl).

### Spec form

```fennel
[tag attrs & children]
```

- `tag` is a keyword: `:Frame` / `:Button` / `:FontString` / `:Texture`.
- `attrs` is a flat map. See "Attribute reference" below.
- Children are nested specs, rendered in order.

Tokens (`theme.spacing.inset`, `theme.spacing.rhythm`, ...) are surfaced
by `let`-binding at the top of each spec function. The spec sees plain
numbers; the renderer never resolves keyword tokens in anchor positions.

### Renderer API

```fennel
(dom.render! parent spec) -> {:root frame :refs {id -> frame}}
```

Single-pass top-down DFS. `:refs` is the only handle to specific
elements after the fact -- mutating code (highlighting an active tab,
re-colouring on state change) reads from `refs` and calls imperative WoW
methods directly. No diff, no patch, no React-style reconciliation.

### Attribute reference

| Attr | Applies to | Effect |
|---|---|---|
| `:id` | any tag | Stores the created object in `refs` under this key. |
| `:name` | `:Frame`, `:Button` | Global frame name (third arg to `CreateFrame`). |
| `:template` | `:Frame`, `:Button` | Frame template (fourth arg). |
| `:size [w h]` | `:Frame`, `:Button`, `:Texture` | `SetSize w h`. |
| `:width n` / `:height n` | same | `SetWidth` / `SetHeight`. |
| `:backdrop :parchment` | `:Frame`, `:Button` | Parchment texture + optional gold edge (`:border?` toggles). Auto-injects `BackdropTemplate` (mandatory since WoW 9.0 / TBC Classic Anniversary; modern `Frame` has no `SetBackdrop` without it). |
| `:backdrop <palette-token>` | same | Solid inset of the palette colour. Same auto-template rule. |
| `:text "..."` | `:FontString`, `:Button` | `SetText`. |
| `:texture-token :gear-icon` | `:Texture` | `SetTexture` from `theme.textures`. |
| `:fill-parent?` | `:Texture` | `SetAllPoints parent`. |
| `:fill true` | `:Frame` | Sugar: topleft+bottomright anchored to parent. |
| `:strata`, `:movable?`, `:mouse?`, `:drag-with` | `:Frame`, `:Button` | Strata / movable / mouse / drag plumbing. |
| `:anchors [[point ref-key ref-point x y] ...]` | any tag | One or more `SetPoint` calls. |
| `:on-click` / `:on-enter` / `:on-leave` | `:Button` | Wires `SetScript` to the supplied fn. |

### Anchor refs

- `:parent` -- reserved. Resolves to the parent the renderer is currently
  walking under (caller-supplied at the top level; the just-built frame
  for nested children).
- Any other keyword -- looked up in `refs`. **Must be earlier in the
  spec** (top-down DFS); forward references throw at render. Unknown ids
  also throw.

### When the spec is the wrong tool

The spec is for layout. The following stay imperative per
§5 anti-patterns and §6 widget rules:

- **State**: `var active-tab`, `pills`, `tab-contents`, frame pools.
- **Mutation on state change**: `restyle-pills!`, recolours, highlight
  swaps. Read frames from `refs`; call WoW methods directly.
- **Event handler bodies**: pass fns as `:on-click` / `:on-enter` /
  `:on-leave` attrs; their bodies are ordinary imperative Fennel.
- **Frame pools**: `acquire!` / `release!` (see example 08). The widget
  owns the pool; the spec describes one instance's tree.
- **`OnUpdate` widgets**: `lockout-timer`, `why-drawer` slide-in. The
  spec defines initial layout; throttled `OnUpdate` scripts are wired
  imperatively after render.
- **AceConfig options panel**: still AceGUI per §2.

### What the renderer does NOT do

- Cache or memoise. Two calls produce two frame trees.
- Diff against a prior spec. Re-render = fresh frames; caller releases
  the old ones via the pool.
- Resolve theme tokens inside attrs. `inset` works because the spec
  function let-bound it from `theme.spacing.inset`.
- Validate attrs against a schema. Unknown attrs are ignored; tag-attr
  mismatches surface as WoW runtime errors (e.g. `SetText` on a
  `:Texture`). A schema lands when we have ten tags.

