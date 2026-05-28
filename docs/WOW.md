# WoW runtime constraints

> What the target platform forbids or punishes. Read this before adding any
> new WoW API call or rewriting a hot path.

## Target

- **TBC Classic Anniversary**, interface number `20505`.
- The `.toc` interface number bumps only when a real content phase ships
  and has been smoke-tested in game.
- Lua **5.1** subset only -- no LuaJIT extensions, no 5.2+ features.

## Lua 5.1 only

The WoW client runs Lua 5.1. Things that look fine in modern Lua and break
silently here:

- No `goto` / labels.
- No bitwise operators -- use the `bit` library or write the math out.
- No 5.3+ integer literals (`1_000`, `0x1p10`). Plain `1000` only.
- No `<close>` / to-be-closed variables.
- No integer division operator `//`. Use `math.floor(a / b)`.
- No `string.pack` / `string.unpack`.

## No `loadstring` / `load` in protected context

The WoW client refuses to compile Lua at runtime in protected scope. We AOT
compile Fennel -> Lua at build time and ship only `.lua` files. **The Fennel
runtime is never shipped.**

## Time and randomness

- Game-relative time uses `GetServerTime()` and `GetGameTime()`. Never
  `os.time()` -- it returns wall-clock time and breaks lockout math when the
  player's machine clock drifts.
- For randomness in the addon's runtime path, use the WoW `math.random`
  via `src/core/wow.fnl`. Domain modules never call `math.random` directly;
  they accept an injected RNG so tests are deterministic.

## No combat-secure code

Routina is a **read-only planner**. It must never:

- Touch secure templates (`SecureActionButtonTemplate` etc.).
- Call `SetAttribute` on a protected frame.
- Run inside a `CombatLockdown` guard.
- Wrap or replace any function the Blizzard UI marks as protected.

If a feature would require any of the above, it does not belong in Routina.

## Performance traps

These cost real frames on a player's machine. Take them seriously even when
the function "feels fast enough":

- **String concatenation in hot loops.** Use `table.concat` for any join
  over more than ~3 pieces. Each `..` allocates a new string.
- **Global lookups in hot loops.** WoW globals (`UnitName`, `GetItemInfo`,
  ...) resolve through the global table on every call. Always destructure
  at module top:
  ```fennel
  (local UnitName _G.UnitName)
  ```
- **`pairs` over arrays.** Use `ipairs` when the table is a sequence; it is
  noticeably faster and stops at the first `nil`.
- **Re-rendering on every tick.** UI updates batch through
  `src/core/events.fnl`; never call `frame:SetText` in a per-frame
  `OnUpdate`.

## API drift

Blizzard ships breaking API changes between patches. Two rules:

1. **Never invent a WoW API signature.** If unsure, check the wiki and link
   it in the commit message:
   https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
2. **Every WoW API call goes through `src/core/wow.fnl`.** That module is
   the only place a renamed function or changed signature gets patched.

See [.claude/examples/02-wow-api-wrapper.fnl](../.claude/examples/02-wow-api-wrapper.fnl).

## SavedVariables format

- `RoutinaDB` is declared in `Routina.toc`. Any new top-level table inside
  it is a schema change -- see [ARCHITECTURE](ARCHITECTURE.md#savedvariables-migrations-are-mandatory).
- Never store function references, frames, or `__index` chains in
  `RoutinaDB`. The WoW client serializes via `pairs` and silently drops
  anything that does not survive.
- Strings stored in `RoutinaDB` should be UTF-8 and < 1024 chars per value
  to keep `.lua` writes fast on logout.

## Things WoW lets you do that you still should not

- Patching another addon's globals. Breaks unrelated addons, unfixable
  bug reports.
- `RegisterEvent("ALL_EVENTS")`. Will work, will tank framerate.
- `SendChatMessage` from a planner. We never spam chat -- ever.
- Hooking `GetItemInfo` results without a cache. The first call returns
  `nil` until the client fetches; subscribe to `GET_ITEM_INFO_RECEIVED`
  through `src/core/events.fnl`.

## Frame and `CreateFrame` discipline

Routina's primary UI is custom-skinned -- see [UI](UI.md) for the visual
language. The runtime constraints that matter here:

- **`CreateFrame` is irreversible.** WoW has no `DestroyFrame`. Every
  widget pools its frames via `acquire!` / `release!`; "released" frames
  park under a hidden parent and are re-used. A widget that allocates
  per-refresh leaks frames for the session.
- **`OnUpdate` runs at the client's framerate.** It is the single most
  expensive callback you can register. Routina restricts `OnUpdate` to
  `lockout-timer` (throttled to 1.0 s, dropping to 0.25 s under 60 s)
  and the `why-drawer` slide-in (200 ms, self-disabling). Any other
  `OnUpdate` requires a written perf justification in review.
- **`SetText` is not free.** Re-setting font strings on every event tick
  causes layout reflow. Diff the text first; skip the call if unchanged.
- **`SetPoint` chains anchor recomputation.** Anchor by parent insets,
  not absolute screen coordinates, and avoid `ClearAllPoints` +
  re-anchor in a hot path -- swap textures or `Show` / `Hide` instead.
- **`GameTooltip` is shared mutable state.** When a Routina widget owns
  the tooltip, set the parchment backdrop on `OnTooltipShow` and restore
  the default on `OnTooltipCleared`. Leaving a custom backdrop on
  `GameTooltip` breaks every other addon that uses it.
- **Tooltip text comes from Blizzard.** Use `SetItemByID` /
  `SetHyperlink`. Never synthesise item lines by string concatenation in
  Fennel -- the result will not match `Item Level`, `Sockets`, or
  `Equip:` lines from Blizzard and tooltips drift fast across phases.
