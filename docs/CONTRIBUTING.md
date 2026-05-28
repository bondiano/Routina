# Contributing

> How to make changes that get merged. Pairs with the topical docs:
> [ARCHITECTURE](ARCHITECTURE.md), [CONVENTIONS](CONVENTIONS.md),
> [WOW](WOW.md), [TESTING](TESTING.md), [TYPES](TYPES.md),
> [UI](UI.md).

## One-time setup

```bash
task deps        # installs busted + luacov into .rocks/
```

If `task` is not installed: https://taskfile.dev.

## Daily commands

```bash
task dev         # watches src/ and recompiles to build/ on change
task build       # compile all src/**/*.fnl to build/**/*.lua
task test        # busted spec/ under luajit (Lua 5.1 API)
task coverage    # luacov report
task lint        # fnlfmt --check + fennel compile-check
task install     # symlink the addon into Interface/AddOns/Routina
task package     # BigWigs packager dry run
task clean       # rm -rf build/
task vendor      # re-download the pinned Fennel compiler
```

Quick loop while writing a domain module:

```bash
task dev &       # leaves a watcher in the background
task test        # rerun after each change
```

## Workflow

1. **Plan before coding.** For anything beyond a small fix, draft the
   approach (in chat or a scratch file) before opening an editor. Use
   Claude's plan mode for non-trivial work.
2. **Read the matching example.** Every kind of module Routina has -- pure
   domain, WoW API wrapper, event dispatcher, Ace3 entry, BiS catalog
   macro, mock, type contract -- has a worked example in
   `.claude/examples/`. Open it before writing.
3. **Write the test first when the contract is clear.** For pure domain
   modules where the math drives the design, the spec is faster to write
   than the implementation. For exploratory work, write the implementation
   alongside the spec, not after.
4. **Run `task lint && task test` before declaring done.** Anything red,
   fix before pushing. No "I'll fix it in CI" pushes.
5. **Regenerate docs after touching `src/domain/`.** Run `/docgen`
   (or the equivalent task command) so `docs/api.md` stays in sync. CI
   fails on drift.

## Commits

Format -- imperative, scope prefix, **<=72 chars** subject:

```
domain: add Bayesian luck score
ui: split weekly tab into header and list
fix: handle empty BiS catalog in route scoring
```

Type prefixes (project convention):

- `feat:` -- new feature
- `fix:` -- bug fix
- `refactor:` -- behaviour-preserving structural change
- `test:` -- adding or extending tests
- `domain:` / `core:` / `ui:` -- scoped change inside that layer
- `docs:` -- docs only
- `chore:` -- deps, build, tooling
- `perf:` -- performance
- `style:` -- formatting only
- `revert:` -- revert a prior commit

Rules:

- **One concept per commit.** Touching domain + ui + tests for one feature
  is fine in one commit; mixing two features is not.
- **No `Co-Authored-By`** trailers. Routina commits are single-authored.
- Body explains *why* if the diff does not. Otherwise omit the body.

## Branches

```
feat/<short>      e.g. feat/lockout-tracker
fix/<short>       e.g. fix/empty-bis-route
refactor/<short>  e.g. refactor/extract-validate
```

Branches are short-lived. Merge to `main` once green; delete the branch.

## When to ask vs decide

**Ask** before:

- Anything in [PRD](PRD.md) §13 open questions.
- Schema changes to `RoutinaDB` (any field added or renamed).
- New external dependencies (`Libs/` addition).
- Breaking SavedVariables compatibility.
- Changing a `.toc` interface number.

**Decide** without asking:

- Implementation details within an established pattern.
- Refactoring inside a single module.
- Adding tests, fixtures, generators.
- Formatting, naming, file splits.
- Following an example pattern literally.

When in doubt, lean on the side of asking once at the start rather than
making 12 small calls that compound into a direction the reviewer would
have redirected.

## Anti-patterns (rejected in review)

- Calling WoW API from `src/domain/*`.
- Mutating shared tables in pure functions.
- `print(...)` for debugging -- use `log:debug`.
- Hardcoded magic numbers without a named binding.
- Functions over 50 lines. Split.
- Files over 300 lines. Split.
- Global mutation outside the `addon` namespace.
- Generating code without reading the matching example first.
- Adding a dependency without updating `Libs/` and `.toc`.
- Adding a WoW API call without first adding a stub to
  `spec/mocks/wow-api.fnl`.
- Hex colours, font paths, or numeric font sizes in `src/ui/widgets/`.
  Read from `src/ui/theme.fnl`.
- `CreateFrame` inside a per-refresh loop, or an unjustified `OnUpdate`
  in any widget body. See [UI](UI.md) §5 and [WOW](WOW.md) for the
  pool / throttle rules.
- AceGUI inside `src/ui/widgets/` or `src/ui/tabs/`. AceGUI is allowed
  only in `src/ui/options.fnl`.

## Releases

Maintainer-only:

1. Run the wowUnit smoke suite in-game.
2. `task package` -- BigWigs packager dry run, confirm no warnings.
3. Tag `vX.Y.Z` on `main`. CI runs the real packager and publishes to
   CurseForge and Wago.
4. Write release notes from the merged-since-last-tag log.

## References

- [WoW API](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)
- [Ace3](https://www.wowace.com/projects/ace3/pages/getting-started)
- [Fennel reference](https://fennel-lang.org/reference)
- [Fennel style](https://fennel-lang.org/style)
- [busted](https://lunarmodules.github.io/busted/)
- [Taskfile](https://taskfile.dev)
