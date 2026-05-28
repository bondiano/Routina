# Type discipline

> Fennel has no static types. We compensate with four layers that together
> catch most of what a real type system would. The canonical worked example
> is [.claude/examples/07-type-contracts.fnl](../.claude/examples/07-type-contracts.fnl).

## The four layers

```
1. Structured docstring   <- read by fennel-ls on hover, by /docgen, by Claude
2. lambda + ?param        <- arity checked at call site
3. schemas.fnl            <- one declarative source of truth for shapes
4. validate.check         <- runtime check at module boundaries
```

Each layer is cheap on its own; together they cover the surface where bugs
actually slip in.

## Layer 1: structured docstrings

Every `lambda` carries a docstring in this exact shape:

```fennel
(lambda M.exactly-k [n k p]
  "Binomial probability: exactly k drops in n runs at rate p.
   Domain:  0 <= p <= 1, 0 <= k <= n, n >= 0.
   Returns: P in [0, 1].
   Errors:  asserts on out-of-range p or k."
  ...)
```

- **One-line summary** -- what it does, no jargon.
- **Domain** -- input types and ranges. Be specific: "n >= 0" beats
  "non-negative integer".
- **Returns** -- output shape. Include units if relevant ("seconds",
  "fraction in [0, 1]").
- **Errors** -- conditions under which the function throws. Omit the line if
  it does not throw.

These docstrings are consumed by:

- `fennel-ls` on hover in your editor.
- `/docgen` -> `docs/api.md` (and CI fails if that file is stale).
- Claude Code when generating a caller -- it reads the docstring before it
  writes the call site.

## Layer 2: `lambda` and `?param`

- Every `M.X` is a `lambda`. `lambda` enforces arity at the call site: a
  missing argument fails loud rather than silently passing `nil`.
- Optional / nilable parameters use `?param`:
  ```fennel
  (lambda M.bayesian-luck [observed-drops observed-runs base-p ?prior]
    ...)
  ```
  `?prior` may be `nil`; the body must handle that case explicitly.
- Private helpers use plain `fn`. Arity-checking your own module's interior
  is noise.

## Layer 3: `src/domain/schemas.fnl`

Domain types -- `Lockout`, `BisItem`, `Activity`, `RouteStep`, ... -- are
declared once as plain data in `src/domain/schemas.fnl`. Each schema is a
table describing the shape:

```fennel
;; Sketch -- the real module lives in src/domain/schemas.fnl
{:Lockout {:id :string
           :instance-id :integer
           :expires-at :integer
           :bosses-killed [:string]
           :owner-key :string}}
```

These schemas drive three things at once:

1. Runtime validation via `validate.check`.
2. Documentation generation (`/docgen` reads them).
3. Test fixture generators in `spec/helpers/gen.fnl`.

When a schema changes, every consumer follows.

## Layer 4: runtime validators at module boundaries

`src/domain/validate.fnl` provides `check` and `coerce`:

```fennel
(local validate (require :domain.validate))
(local schemas (require :domain.schemas))

;; At a module boundary: validate the incoming shape.
(lambda M.add-lockout [db raw]
  (let [lockout (validate.check schemas.Lockout raw)]
    ...))
```

**Run validators where data crosses a trust boundary**, not in hot loops:

- WoW API payload -> domain (after the dispatcher normalizes it).
- SavedVariables load (`db.version` mismatch triggers migration first,
  then validate).
- User input from AceConfig.

Inside a pure domain function that has already received validated input,
do not re-validate. The cost is real and the bug is upstream.

## What this combination buys you

- **Wrong shape from WoW** -- caught at the event dispatcher boundary, not
  five frames later when a downstream `tset` blows up.
- **Wrong arity at a call site** -- caught by `lambda` at the call, not by
  a confusing `nil` deep in the body.
- **Missing parameter in the caller's mental model** -- caught by reading
  the docstring (which `fennel-ls` shows on hover, and `/docgen` publishes).
- **Stale documentation** -- caught by CI when `docs/api.md` no longer
  matches the docstrings.

## When this is not enough

If a module needs richer guarantees -- "this list is sorted", "these two
fields are mutually exclusive" -- write a property test in
[TESTING](TESTING.md) rather than encoding the invariant in a comment.
Tests fail; comments lie.
