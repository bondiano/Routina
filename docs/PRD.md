# Routina -- Claude Code Instructions

> WoW addon for TBC Classic Anniversary. Weekly route planner with BiS-aware probability engine.
> Written in Fennel, compiles to Lua 5.1.
> Read `PRD.md` for full product context. Worked examples in `.claude/examples/`.

## Mission rules (non-negotiable)

- **Read `PRD.md` first** if you don't already have product context.
- **Read the matching example in `.claude/examples/` before writing a new module of that kind.** They encode patterns this project uses.
- **Never invent WoW API signatures.** If unsure, ask. WoW Wiki: https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
- **Pure domain, imperative shell.** `src/domain/*` must be pure (no WoW API calls, no SavedVariables mutation). All side effects in `src/core/` and `src/ui/`.
- **Tests come with code, not after.** Every PR that touches `src/domain/` must include a `_spec.fnl` change.

## Stack

| Layer | Tool |
|---|---|
| Source | Fennel 1.6+ |
| Target | Lua 5.1 (WoW subset) |
| Framework | Ace3 (AceAddon, AceDB, AceEvent, AceConfig, AceGUI, AceLocale) |
| Tests | busted + Fennel searcher; wowUnit for in-game |
| Build | go-task (Taskfile.yml) + GitHub Actions + BigWigs packager |

## Bash commands

```bash
task deps        # one-time: install busted + luacov into a luajit tree (.rocks/)
task dev         # watch src/ and recompile to build/ on change
task build       # compile all src/**/*.fnl to build/**/*.lua
task test        # busted spec/ under luajit (Lua 5.1 API, like WoW)
task coverage    # luacov report (% is approximate for Fennel sources)
task package     # BigWigs packager dry run
task lint        # fnlfmt --check + fennel compile-check
task install     # symlink the addon into Interface/AddOns/Routina
task clean       # rm -rf build/
```

## Project layout

```
src/
├── core/        # AceAddon entry, event dispatcher, SavedVariables
├── domain/      # PURE. No WoW API. Math, routing, catalog, lockout logic.
└── ui/          # Frames, tabs, theming
spec/            # busted tests, mirrors src/ layout
spec/mocks/      # Stubs for WoW globals
Libs/            # Vendored Ace3 etc (untouched)
build/           # gitignored .lua output from Fennel compilation
.claude/
├── examples/    # Read these BEFORE writing new modules
├── agents/      # Sub-agents for specific tasks
└── commands/    # Slash commands
```

## Fennel conventions

- **Naming**: `kebab-case` for everything except WoW globals; locals destructure WoW APIs at module top: `(local UnitName _G.UnitName)`.
- **Predicates** end with `?`: `lockout-active?`, `can-roll?`. Never `is-*` prefix.
- **Mutating functions** end with `!`: `flush!`, `reset-weekly!`. Pure variant has no bang.
- **Threading**: prefer `(->>)` for collection pipelines, `(->)` for object chains.
- **`case` not `match`** for new code (per current Fennel guidance). `match` is deprecated alias.
- **`lambda` for everything on `M.`** (public API) -- enforces arity. `fn` for private helpers. `#(...)` for short closures.
- **`?param` for nilable args** in `lambda` signatures.
- **Docstrings mandatory on every `lambda`**. Use structured format (see Type discipline section).
- **`fnlfmt` is canonical formatter**. Never argue about whitespace.

## WoW constraints (hard)

- **Lua 5.1 only.** No `goto`, no bitwise operators without `bit` lib, no integer literals 5.3+, no `<close>`.
- **No `loadstring`/`load` in protected context.** AOT compile only. Fennel runtime is never shipped.
- **No `os.time`, `os.date` for game time** -- use `GetServerTime()`, `GetGameTime()`.
- **No combat-secure code.** This addon is read-only planning. Never touch secure templates, `CombatLockdown`, `SetAttribute` on protected frames.
- **`.toc` interface number** = 20505 (TBC Classic Anniversary). Bump per phase only after testing.
- **String concatenation in hot loops kills Lua.** Use `table.concat` for >3 pieces.
- **Globals are slow.** Always `(local Name _G.Name)` at module top for repeated WoW API access.

## Architecture principles

- **Pure core, imperative shell.** `src/domain/*` is pure Fennel -- given same input, same output, no I/O, no time, no random (pass seed if needed for Monte Carlo).
- **Event dispatcher is single source of side-effects entry.** All WoW events go through `src/core/events.fnl` `case` dispatch.
- **SavedVariables migration is mandatory** for any schema change. Bump `db.version`, write migration in `src/core/saved-vars.fnl`.
- **No singletons.** Modules export tables of functions. Addon state lives in `addon.db` and is passed explicitly.
- **No string-keyed magic.** Activity types, slot names, classes -- Fennel keywords (`:priest`, `:shadow`, `:head`).

## Testing approach

- **Tier 1 -- busted (CI):** all `src/domain/*` and pure parts of `src/core/`. Target >=85% coverage.
- **Tier 2 -- wowUnit (manual pre-release):** UI smoke, real event subscriptions.
- **Property-based tests** required for `drop-chance` and `routing` modules. Use generators in `spec/helpers/gen.fnl`.
- **Mocks live in `spec/mocks/wow-api.fnl`.** When writing a module that calls WoW API, the WoW API stub goes in mocks FIRST.
- **Tests are also Fennel.** Spec files end in `_spec.fnl`. busted loads them through `spec/helper.lua`.

## Type discipline (no static types -- compensate with these 4 levels)

See `.claude/examples/07-type-contracts.fnl` for the canonical pattern.

1. **Structured docstrings** on every public fn. Format:
   ```
   "One-line summary.
    Domain:  <param-types-and-ranges>
    Returns: <output-shape>
    Errors:  <thrown-conditions, if any>"
   ```
   These are read by `fennel-ls` on hover, by `docgen` for `docs/api.md`, and by Claude when generating callers.

2. **`lambda` for public API**, `fn` for private. `lambda` enforces arity at call time; use `?param` for nilable parameters. Every `M.X` must be `lambda`.

3. **Schemas in `src/domain/schemas.fnl`**. Domain types (Lockout, BisItem, Activity, etc.) declared once as data. Schemas drive runtime validation, doc generation, and test fixture generators.

4. **Runtime validators at module boundaries.** WoW API -> domain crossing, SavedVariables load, user input -- validate via `(validate.check schemas.X value)`. Never inside hot loops.

Run `/docgen` after touching `src/domain/*` to regenerate `docs/api.md`. CI fails if it's stale.

## Anti-patterns (REJECT if you see these in generated code)

- ❌ Calling WoW API from `src/domain/*`.
- ❌ Mutating tables in pure functions (use `vim.tbl_deep_extend`-style merge or recreate).
- ❌ `print(...)` for debugging -- use addon's `log:debug` channel.
- ❌ Hardcoded magic numbers without named binding.
- ❌ Functions >50 lines. Split.
- ❌ Files >300 lines. Split.
- ❌ Global mutation outside `addon` namespace.
- ❌ Generating code without reading the matching example first.
- ❌ Adding a new dependency without updating `Libs/` and `.toc`.

## Workflow expectations

- Make a plan before coding. Use `plan mode` for non-trivial work.
- After a series of changes: `task lint && task test`. Fix anything red before declaring done.
- Commits: imperative mood, scope prefix, <=72 chars subject. Example: `domain: add Bayesian luck score`.
- Branch naming: `feat/<short>`, `fix/<short>`, `refactor/<short>`.
- One concept per commit. If touching domain + ui + tests for one feature -> still one commit, but never mix two features in one commit.

## When to ask vs decide

- **Ask** for: anything in PRD §13 (open questions), schema changes, new external deps, breaking changes to SavedVariables.
- **Decide** without asking: implementation details within established patterns, refactoring within a module, test additions, formatting.

## References

- WoW API: https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
- Ace3: https://www.wowace.com/projects/ace3/pages/getting-started
- Fennel reference: https://fennel-lang.org/reference
- Fennel style: https://fennel-lang.org/style
- busted: https://lunarmodules.github.io/busted/