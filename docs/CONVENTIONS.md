# Conventions

> Fennel style and code-shape rules. Pairs with [TYPES](TYPES.md) (what every
> function must document) and [WOW](WOW.md) (what the runtime allows).

## Naming

- `kebab-case` for everything Fennel-native: locals, functions, modules,
  file names. `lockout-active?`, `plan-week`, `bis-catalog.fnl`.
- WoW globals destructure at the top of the module, keeping their original
  CamelCase:
  ```fennel
  (local UnitName _G.UnitName)
  (local GetServerTime _G.GetServerTime)
  ```
- Predicates end with `?`: `lockout-active?`, `can-roll?`, `bis-slot?`.
  **Never** `is-*` prefix.
- Mutating functions end with `!`: `flush!`, `reset-weekly!`. The pure
  variant (if both exist) has no bang.
- Constants UPPER-KEBAB only when they are honest constants from the WoW API
  (`MAX-PLAYER-LEVEL`); otherwise plain kebab.

## Threading

- `(->>)` for collection pipelines (data is the last argument).
  ```fennel
  (->> items
       (filter has-stat?)
       (map score)
       (sort >))
  ```
- `(->)` for object chains and step-by-step transforms.
  ```fennel
  (-> player
      (apply-buffs)
      (apply-gear)
      (effective-hit))
  ```

## `case` not `match`

`case` is the current Fennel pattern-matching form. `match` is a deprecated
alias kept only for old code. Write new code with `case`.

## `lambda` for public API, `fn` for private

- Every entry on the module's exported `M` table is a `lambda`. `lambda`
  enforces arity at the call site, so a missing argument fails loud rather
  than silently passing `nil`.
- Nilable parameters use the `?param` form:
  ```fennel
  (lambda M.bayesian-luck [observed-drops observed-runs base-p ?prior]
    "...")
  ```
- Private helpers inside a module use `fn` -- arity-checking the inside of
  your own module is noise.
- Short closures use `#(...)`:
  ```fennel
  (filter #(> $.weight 0) items)
  ```

## Docstrings are mandatory

Every `lambda` carries a structured docstring. See [TYPES](TYPES.md) for the
format. `task lint` does not yet enforce this; reviewers do.

## Formatting

- `fnlfmt` is the canonical formatter. Never argue about whitespace.
- `task lint` runs `fnlfmt --check`. If it complains, run `fnlfmt --fix`.
- Indentation: 2 spaces, as `fnlfmt` produces. No tabs in `.fnl` files.

## File and function size

- Functions over **50 lines** must be split. Almost always a sign of mixed
  concerns.
- Files over **300 lines** must be split. Group by capability, not by
  "private helpers" vs "public API" -- the export shape already conveys
  that.

## Code-style preferences

- **Functional first.** Prefer pure transforms over mutating loops. Prefer
  declarative pipelines (`->>`) over imperative `for` when the data flows
  linearly.
- **Immutability by default.** When a function "updates" a record, it
  returns a new table with the changed field, not a mutated copy of the
  input.
- **Descriptive names over short ones.** `expected-runs-until-drop` beats
  `eR`. The compiler does not pay for long identifiers; readers do.
- **Small functions.** A function that does one thing is also a function you
  can test in one assertion.

## Magic numbers

Any literal number that isn't `0`, `1`, or an obvious index must be a named
local. Reviewers reject `* 0.85` without a `(local raid-bonus 0.85)` above it.

## Logging

Never `print`. Use the addon log channel (`log:debug`, `log:info`,
`log:warn`). Debug output left in shipped code is a release blocker.

## UI conventions

Routina's primary panel is built on raw `CreateFrame`, not AceGUI. The
full visual language lives in [UI](UI.md); the code-shape rules are:

- **Theme tokens only.** No hex literals, font path literals, or numeric
  font sizes outside `src/ui/theme.fnl`. Reviewers grep
  `src/ui/widgets/` for `[0-9A-Fa-f]\{6\}` and reject hits.
- **Frame pools, never per-refresh `CreateFrame`.** Each widget exports
  `acquire!` / `release!`. Released frames park under a hidden parent
  (WoW has no `DestroyFrame`). Pattern in
  [.claude/examples/08-ui-widget.fnl](../.claude/examples/08-ui-widget.fnl).
- **Pure view-model, separate `set!`.** Map data to a render-spec in a
  pure fn (busted-testable); apply the spec to a frame in `M.set!`
  (wowUnit territory).
- **`OnUpdate` is rationed.** Only `lockout-timer` (>=1.0 s throttle)
  and `why-drawer` slide-in (200 ms, self-disabling) use `OnUpdate`.
  Any other use is rejected without a written perf justification.
- **No tooltip text synthesis.** Use `GameTooltip:SetItemByID` /
  `GameTooltip:SetHyperlink`. Never build tooltip text by `..` in
  Fennel.
- **AceGUI only in `src/ui/options.fnl`.** The Options panel stays
  native; the rest of the UI is custom.
