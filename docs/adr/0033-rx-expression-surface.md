# ADR-0033: Stage ordinary expression syntax with rx%

- Status: Accepted
- Date: 2026-08-24

## Context

Every staged expression in the repository was written by hand-applying
`RxExpr` constructors, so a value as small as
`if count % 2 == 0 then "even" else "odd"` took six nested constructor
applications, and `PLAN.md`'s illustrative component surface
(`derived doubled : Int := count * 2`, `s!"Count: {count}"`) had no
implementation. ADR-0006 explicitly reserved a later surface parser that
targets the same public core without changing graph, proof, backend, or host
layers.

## Decision

Add a scoped `rx%` term surface in `LeanRx.Elab.Rx` that maps ordinary Lean
operator syntax onto typeclass-directed smart constructors in
`LeanRx.Core.RxOps`:

- `+ - * %` and `< ≤ > ≥ == !=` select the exact closed `BinaryPrim` through
  `RxAdd`/`RxSub`/`RxMul`/`RxMod`/`RxOrd`/`RxEqPrim` instances for `Int`,
  `Nat`, and (`==`/`!=`) `String`.
- `&& || !` map onto the boolean primitives, `++` onto `String.append`,
  prefix `-` onto `Int.neg`, and `if _ then _ else _` onto the staged
  conditional with the canonical dependency union.
- `toString` and `s!"..."` interpolation stage through `RxToText`
  (`Int.toString`, `Nat.toString`, identity on `String`), folding
  interpolation chunks with `String.append` exactly as the hand-written trees
  did.
- Numeric, string, and boolean literals become `ScalarLiteral`s through
  `RxNumLit` or directly.
- Every remaining leaf elaborates through a typed atom step: schema fields
  stage as `RxExpr.read`, staged expressions pass through unchanged,
  `ScalarLiteral` values wrap in `RxExpr.literal`, and closed
  `Bool`/`Int`/`Nat`/`String` host values lift into literals through
  `RxLiftLit`. Any other type fails with the stable diagnostic
  `error[LRX-RX-001]` at the leaf's source range.

The smart constructors only assemble existing public constructors; `rx%`
introduces no new primitive, dependency rule, or runtime code. The staged tree
is exactly the tree the explicit constructor API builds, which
`Test/Elab/Rx.lean` pins structurally and `check_examples.sh` pins through the
unchanged playground golden output.

## Consequences

- `examples/Counter.lean`, `examples/DiamondLab.lean`,
  `examples/LeanRxDocs.lean`, `examples/ExpressionPlayground.lean`,
  `examples/GraphLab.lean`, and `examples/GraphFixtures.lean` no longer
  hand-write `RxExpr` trees; the explicit constructor API remains public and
  is still exercised directly by the core test suite.
- `rx%` is scoped inside `LeanRxDsl` like the component and JSX surfaces, so
  the added token cannot collide with ordinary identifiers unless opened.
- The `Test/fixtures/compile-fail/UnstageableRxAtom.lean` fixture pins the
  `LRX-RX-001` diagnostic for unstageable host values.
- Staging stays limited to the closed scalar language; collections, effects,
  and host-only types remain unrepresentable in `rx%` by construction.
