# ADR-0036: Sugar component items and bind events by reference

- Status: Accepted
- Date: 2026-08-24

## Context

The `component` command was a thin wrapper: every item repeated its explicit
specification value (`state count := ValueSpec.state count (.int 1);`,
`event addTwo := addTwo;`) and views bound events by string
(`onClick="addTwo"`), so the PLAN.md M4 surface sketch
(`state count : Int := 1`, `event increment => set count (count + 1)`,
`onClick={increment}`) remained undelivered while every declaration name
appeared two or three times per line.

## Decision

Keep the explicit right-hand sides valid and layer the sketched sugar over
the same checked specification values:

- `state name : Type := literal;` lowers to `ValueSpec.state name (.…)` for
  the closed scalar literal types `Int`, `Nat`, `Bool`, and `String`
  (`LRX-ELAB-105` otherwise). The declaration identifier doubles as the
  schema `Field` reference, so the field definition and the surface name stay
  aligned by construction.
- `derived name := rx% …;` stages the expression and wraps it as
  `ValueSpec.computed name (rx% …)`; a right-hand side that already
  elaborates to a `ValueSpec` passes through unchanged (type-directed, like
  `rx%` leaves).
- `event name := step then step …;` builds the `Update` sequence left-fold
  from steps `set field (expr)` (the expression stages through `rx%`) and
  `dispatch event`; a single non-step term still passes through as an
  explicit `EventSpec`. Malformed steps report `LRX-ELAB-104`.
- `event name (param : Type) := set field param;` declares an M6
  `TypedEventSpec` whose payload assigns the parameter to a source field
  (ADR-0037); any other right-hand side reports `LRX-ELAB-108`.
- Inside an inline `jsx%` view, `onClick={name}` (and the payload attributes)
  first checks the component's declared event inventory and lowers to the
  same checked string binding; outside a component, `onClick={term}` reads
  the name from an elaborated `EventSpec`/`TypedEventSpec`, so unknown
  references are ordinary unknown-identifier errors at the attribute span and
  kind mismatches keep `LRX-VIEW-006`/`-017`.

## Consequences

- `examples/Counter.lean` and `examples/DiamondLab.lean` define their
  `component` blocks entirely in the sugared surface (inline `rx%` sinks,
  `then` sequences, `dispatch` nesting, reference bindings), and the
  generated `Counter.mjs`/`DiamondLab.mjs` stay byte-identical to the
  wrapper-style output; manifests differ only through span-bearing graph
  hashes.
- Surface declarations still align against the checked specification
  (`LRX-ELAB-103`), so a mismatch between the sugar and the produced value
  (for example `state` naming a derived value) remains a hard error.
- Multi-step updates read left to right; nested `then` chains fold into the
  same left-associated `Update.sequence` tree the explicit API produced.
