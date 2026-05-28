# Testing

> Two tiers, two purposes. Tier 1 catches every regression in CI; Tier 2
> catches the few classes of bug a real WoW client surfaces.

## Tier 1 -- busted (CI)

- Runs under `luajit` with the Lua 5.1 API, matching WoW.
- Covers **all** of `src/domain/` and the pure parts of `src/core/`.
- Property-based where the math warrants it (see below).
- Target: **>=85% line coverage** on `src/domain/`.
- Fails the build on any red test; never merged red.

Run locally:

```bash
task test       # once
task coverage   # busted + luacov report
```

Spec files end in `_spec.fnl`. busted loads them through
`spec/helper.lua`, which registers the Fennel searcher so the same files
the addon ships are exercised by tests.

## Tier 2 -- wowUnit (manual, pre-release)

- Runs inside an actual WoW client via the wowUnit addon.
- Used for: UI smoke (open tabs, click buttons, `/reload`), event
  subscriptions on real Blizzard payloads, AceDB persistence end-to-end.
- Not in CI. Maintainer runs the suite before tagging a release.
- A failed wowUnit run blocks the release tag, not the merge.

## Property-based testing

`src/domain/drop-chance.fnl` and `src/domain/route.fnl` (when it lands) have
enough invariants that example-based tests miss long-tail bugs. Both ship
property tests using generators in `spec/helpers/gen.fnl`.

Examples of properties worth asserting:

- `at-least-one(p, n)` is monotonic in `n` for any fixed `p in [0, 1]`.
- `at-least-one(p, 0) == 0` and `at-least-one(0, n) == 0` for all valid `n`.
- `sum_k(exactly-k(n, k, p)) == 1` for all valid `n`, `p`.
- `effective-rate(p, c) * c <= p + epsilon` for all `c >= 1`.
- `plan-week(player, db)` is deterministic given the same `(player, db,
  seed)` triple.

Reach for property tests when the function's contract is more naturally
stated as "for all inputs ..." than as "input X returns Y".

## Mocks

- WoW globals are stubbed in `spec/mocks/wow-api.fnl`. **When you add a new
  WoW API call, add the stub here first.** No PR adds a real call without
  a mock.
- Mocks return deterministic, minimum-viable shapes. They are not a model
  of WoW; they are just enough surface for the domain to type-check at
  runtime.
- Time and randomness are injected by the caller in tests. Never read
  `os.time`, `GetServerTime`, or `math.random` from a domain spec.

## What not to test

- Generated `build/*.lua`. Specs target the `.fnl` sources via the Fennel
  searcher; the Lua output is a build artifact.
- `CreateFrame` pixel layout. wowUnit handles that.
- Third-party `Libs/` code. We pin it; we do not own it.

## UI widgets

Custom-`CreateFrame` widgets (see [UI](UI.md)) split into two halves for
testing:

- **Pure view-model** (`M.view-model`, formatters) -- busted-tested in
  `spec/ui/widgets/<name>_spec.fnl`. Every input range, every nil case.
- **Frame application** (`M.set!`, `M.acquire!`, `M.release!`) --
  wowUnit smoke only. The mock `CreateFrame` in `spec/mocks/wow-api.fnl`
  records calls so busted can assert structural facts ("acquired three
  item-pills, released the prior set") without rendering pixels.

A new widget ships with: a view-model spec in busted **and** a line
added to the wowUnit smoke checklist below.

## wowUnit smoke checklist

Maintainer-run before a release tag. Failing this blocks the tag, not
the merge.

- [ ] `/routina` opens and closes the root frame.
- [ ] Plan, Lockouts, BiS tabs all render at least one card each on a
      fixture character.
- [ ] Clicking `Why?` on a Plan card opens `why-drawer`; pressing `Esc`
      closes it.
- [ ] Switching tabs while `why-drawer` is open closes the drawer.
- [ ] `lockout-timer` ticks down without spiking the addon CPU column.
- [ ] Hovering an `item-pill` shows the Blizzard tooltip with a
      parchment backdrop; the tooltip's default backdrop is restored on
      `OnTooltipCleared`.
- [ ] Options panel opens, font scale persists across `/reload`.

## Coverage caveat

`luacov` measures the **compiled Lua** output, not the Fennel source. A
single `(case ...)` expands to several Lua branches, so the percentage is
approximate. Treat 85% as a floor for catching the "I forgot to test the
nil branch" class of bug, not a precise target.
