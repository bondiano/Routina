# Routina

WoW addon for TBC Classic Anniversary. Weekly route planner with BiS-aware probability engine.

Written in [Fennel](https://fennel-lang.org/), compiles to Lua 5.1 (WoW subset).

## Stack

| Layer | Tool |
|---|---|
| Source | Fennel 1.6+ |
| Target | Lua 5.1 |
| Framework | Ace3 (AceAddon, AceDB, AceEvent, AceConfig, AceGUI, AceLocale) |
| Tests | busted + Fennel searcher; wowUnit for in-game |
| Build | go-task (Taskfile.yml) + GitHub Actions + BigWigs packager |

## Project layout

```
src/
├── core/        # AceAddon entry, event dispatcher, SavedVariables
├── domain/      # PURE. No WoW API. Math, routing, catalog, lockout logic.
└── ui/          # Frames, tabs, theming
spec/            # busted tests, mirrors src/ layout
spec/mocks/      # Stubs for WoW globals
Libs/            # Vendored Ace3 etc (untouched)
vendor/          # Pinned build-time Fennel compiler (see below)
build/           # gitignored .lua output from Fennel compilation
```

## Tasks

```bash
task deps        # one-time: install busted + luacov into a luajit tree (.rocks/)
task dev         # watch src/ and recompile to build/ on change
task build       # compile all src/**/*.fnl to build/**/*.lua
task test        # busted spec/ under luajit (Lua 5.1 API, like WoW)
task coverage    # luacov report
task package     # BigWigs packager dry run
task lint        # fnlfmt --check + fennel compile-check
task install     # symlink the addon into Interface/AddOns/Routina
task clean       # rm -rf build/
task vendor      # re-download the pinned Fennel compiler into vendor/
```

## `vendor/`

`vendor/fennel.lua` is the pinned build-time Fennel compiler. It is committed to the repo so that `task build` and `task test` work on a clean clone without a network round-trip, and so the compiler version is locked.

- Do **not** edit this file by hand.
- To bump the version, change `FENNEL_VERSION` in `Taskfile.yml` and run `task vendor`, then commit the result.
- `vendor/` is excluded from the released addon zip via `.pkgmeta` -- only the build tooling uses it.

## Architecture principles

- **Pure core, imperative shell.** `src/domain/*` is pure Fennel -- given the same input, the same output, no I/O, no time, no random (pass a seed if needed for Monte Carlo).
- **Event dispatcher is the single entry for side effects.** All WoW events go through `src/core/events.fnl`.
- **SavedVariables migrations are mandatory** for any schema change. Bump `db.version`, write the migration in `src/core/saved-vars.fnl`.
- **No singletons.** Modules export tables of functions. Addon state lives in `addon.db` and is passed explicitly.

## Testing

- **Tier 1 -- busted (CI):** all `src/domain/*` and pure parts of `src/core/`. Target >=85% coverage.
- **Tier 2 -- wowUnit (manual pre-release):** UI smoke, real event subscriptions.
- Property-based tests required for `drop-chance` and `routing`. Generators in `spec/helpers/gen.fnl`.
- WoW API mocks live in `spec/mocks/wow-api.fnl`.

## References

- [WoW API](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)
- [Ace3](https://www.wowace.com/projects/ace3/pages/getting-started)
- [Fennel reference](https://fennel-lang.org/reference)
- [Fennel style](https://fennel-lang.org/style)
- [busted](https://lunarmodules.github.io/busted/)
