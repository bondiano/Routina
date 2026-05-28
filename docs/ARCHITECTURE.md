# Architecture

> How Routina is organized and why. Pairs with [CONVENTIONS](CONVENTIONS.md)
> (how code looks) and [WOW](WOW.md) (what the target platform forbids).

## Core principle: pure core, imperative shell

```
+--------------------------------+
|   src/ui/   (CreateFrame)      |  side effects: frames, input, tooltips
+-------------+------------------+
              |
+-------------v------------------+
|   src/core/  (Ace3, WoW)       |  side effects: events, time, SavedVariables
+-------------+------------------+
              |
+-------------v------------------+
|   src/domain/  (PURE)          |  no I/O, no time, no random, no globals
+--------------------------------+
```

- **`src/domain/*` is pure Fennel.** Given the same input it returns the same
  output. No WoW API calls. No `os.time`. No `math.random` (callers inject a
  seeded RNG). No SavedVariables mutation. Anything else makes the module
  untestable in busted.
- **`src/core/*` owns side effects.** WoW events, AceDB writes, timers,
  randomness. It feeds the domain pure inputs and writes the domain's pure
  outputs back to game state.
- **`src/ui/*` owns presentation.** Custom `CreateFrame` widgets (not
  AceGUI -- see [UI](UI.md) §2), frame pools, theming. AceGUI is allowed
  only in `src/ui/options.fnl` for the Options panel. Talks to `core` for
  data, never to `domain` directly for I/O.

The benefit: every probability, every routing decision, every BiS lookup is
testable with `task test` in milliseconds, without a running WoW client.

## Event dispatcher is the single side-effect entry

All WoW events flow through `src/core/events.fnl`, which `case`-dispatches on
event name. Domain modules never call `AceEvent:RegisterEvent` themselves;
they subscribe to *our* events, which we re-emit after validating and
normalizing the WoW payload.

Why: there is exactly one place to mock for tests, one place to gate by
client build, one place to add logging.

See [.claude/examples/03-event-dispatcher.fnl](../.claude/examples/03-event-dispatcher.fnl).

## SavedVariables migrations are mandatory

Any schema change to `RoutinaDB` bumps `db.version` and ships a migration in
`src/core/saved-vars.fnl`. Old characters loading new code must not crash and
must not silently lose data.

The migration list is append-only. Never edit a shipped migration.

## No singletons

Modules export a table of functions (`M`). Addon state lives on `addon.db`
and is passed explicitly to anything that needs it. There is no module-level
mutable variable holding "the current player" or "the active plan".

Why: tests can construct any addon-shaped table they want without a global
reset between cases.

## No string-keyed magic

Activity types, slot names, classes, specs -- all Fennel keywords (`:priest`,
`:shadow`, `:head`). Never bare strings, never integer codes. `case` on
keywords is fast and exhaustive; a typo is a hard error, not a silent miss.

## Project layout

```
src/
  core/        AceAddon entry, event dispatcher, SavedVariables, WoW wrapper
  domain/      Pure logic: math, routing, catalog, lockout, schemas
  ui/          Root frame, tabs, theme tokens, formatters
    widgets/   Pooled CreateFrame widgets (activity-card, item-pill, ...)
    tabs/      Per-tab content modules (weekly, lockouts, bis)

spec/          busted tests, mirrors src/ layout
  mocks/       Stubs for WoW globals
  helpers/     Test fixtures and generators

Libs/          Vendored Ace3 etc. Do not edit.
vendor/        Pinned Fennel compiler. Build-time only, not shipped.
build/         gitignored .lua output from Fennel compilation
Locales/       AceLocale strings, enUS first

.claude/
  examples/    Canonical worked patterns. Read before writing a new module.
  agents/      Sub-agents (bis-curator, domain-module, test-writer, ui-widget)
  commands/    Slash commands (compile, test, package, docgen)

docs/          Human-facing docs (this folder)
```

## Module boundary checklist

Before merging a new module, confirm:

- [ ] If it lives in `src/domain/`, it imports nothing from `src/core/` or
      `src/ui/` and references no WoW globals.
- [ ] All public functions are `lambda` with structured docstrings.
- [ ] All inputs at the boundary are validated against
      `src/domain/schemas.fnl` via `validate.check`.
- [ ] All mutation is local to the function (no shared table writes).
- [ ] A matching `_spec.fnl` exists with property-based tests where the math
      warrants it.
- [ ] If it consumes a WoW event, that event is dispatched through
      `src/core/events.fnl`, not subscribed to directly.
