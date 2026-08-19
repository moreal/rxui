# ADR-0011: Exclude modulo-normalized `Fin` literals from selection construction

- Status: Accepted
- Date: 2026-08-19

## Context

The M6 plan originally required an invalid numeric literal for `Fin n` to fail
compilation. On the pinned Lean 4.33 toolchain, the minimal reproduction

```lean
#eval (3 : Fin 3).val
```

compiles and prints `0`: the standard `OfNat (Fin n)` instance normalizes the
literal modulo `n`. A public `TabsSpec.create ... (3 : Fin 3)` boundary would
therefore accept a valid value but silently lose the caller's out-of-range
intent. The original negative fixture was a false assumption about Lean.

## Alternatives considered

- Accept raw `Fin` values because every resulting value is in range. This keeps
  memory safety but silently selects the wrong tab for an out-of-range literal.
- Replace `Fin` state with a custom index type. This weakens the architecture's
  explicit dependent-type example and duplicates a standard type.
- Add a custom term elaborator that rejects numeric `Fin` syntax. This expands
  the public language and elaborator TCB for no additional invariant.

## Decision

Tabs continues to store selection and event payloads as `Fin (n + 1)`, but its
public initial-selection API never accepts a caller-authored raw `Fin` value.
`TabsSpec.create` selects zero. `TabsSpec.createAt` accepts the intended `Nat`
and an explicit proof that it is below `n + 1`, then constructs the `Fin`
internally. Generated click handlers likewise originate only from enumerated
vector indices.

## Consequences

Out-of-range intent is a compile error at the public boundary, while the browser
still stores only the erased finite index. Existing callers selecting a nonzero
initial tab migrate from a `Fin` argument to `createAt value proof`. Direct use
of Lean's raw `Fin` numeric literals outside this API keeps Lean's standard
semantics and is not redefined by LeanRx.

## Validation

The toolchain premise is locked by a native regression asserting
`(3 : Fin 3).val == 0`. Compile-pass fixtures use `createAt 1 (by decide)`.
The negative fixture attempts `createAt 3 (by decide)` for three tabs and fails
before lowering. Browser handlers remain exactly the enumerated indices 0–2.
