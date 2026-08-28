# ADR-0073: Misshapen child references are rejected at the typed-application fallback

- Status: Accepted
- Date: 2026-08-28

## Context

A capitalized head in a typed component view lowers three ways
(`typedElement`): attr-less and child-less to the plain child
reference (ADR-0039), empty-children with only `name="text"` or
rewritten `name = propRef% index` attributes to the prop-carrying
child reference (ADR-0042/0068), and everything else to the
`componentCall` typed-application fallback. The fallback exists for
heads *without* a checked spec — ADR-0039: "a `<Child/>` whose
`Child_spec` is not in scope still elaborates as a term application,
so template-function views keep working unchanged" — and that
surface is live: `Test/Elab/ViewSurface.lean` composes
`<Metric value={metricValue}/>` where `Metric` is an ordinary view
template function.

This round surveyed what a head *with* a checked spec in scope sees
when its shape leaves the child-reference contract. The component
command generates `Chip_schema`/`Chip_spec`/`Chip_check`/
`Chip_declarations` — no term named `Chip` — so the fallback
application can only die in the elaborator. All three misuse shapes
died identically, on a NestLab-derived reproduction:

- `<Chip tag="x"> ["extra"]` (non-empty children),
- `<Chip tag={heading ++ "!"}/>` (composed dynamic value — the
  forwarding rewrite claims only one bare declared-prop identifier),
- `<Chip onClick={notAnEvent}/>` (non-prop attribute whose value the
  RHS sugar does not claim)

each reported `Unknown identifier 'Chip'` at the head's span, plus
the `sorryAx` cascade — maximally misleading, since the user is
looking at a checked component that manifestly exists, and nothing
names the composition contract they missed.

Two neighboring shapes never reach the fallback and already carry
adequate diagnostics; the survey pins them as the boundary:

- `<Chip onClick={declaredEvent}/>` — the component RHS sugar
  (ADR-0038) rewrites a declared event reference to the string form
  first, so `literalPropPairs` accepts it and the props path reports
  `LRX-ELAB-112` ("declares immutable props (tag); got (onClick)"),
  which names the declared inventory.
- `<Ghost label={title}/>` with no `Ghost_spec` — the forwarding
  rewrite produced `propRef%`, and the props path reports
  `LRX-ELAB-130` (forwarding nests checked children only).

## Decision

**Reject at the fallback with a dedicated term-elab diagnostic;
never at the macro.** A macro-time rejection (candidate b) is
impossible without breaking ADR-0039: the misuse shape
`name={composedTerm}` is byte-identical to the legitimate spec-less
application `<Metric value={metricValue}/>`, and the macro cannot see
whether `_spec` resolves. So `typedElement` now wraps the fallback in
`leanrx_jsx_component_fallback% head reason call`, a term elaborator
that checks `resolvesToComponentSpec` — the same helper the child
reference elabs use — and either throws or elaborates the wrapped
application unchanged:

```
error[LRX-ELAB-132]: Chip resolves to the checked component spec
Chip_spec; a child reference takes no children — the child's content
lives in its own component view
```

for non-empty children, and

```
error[LRX-ELAB-132]: Chip resolves to the checked component spec
Chip_spec; a child reference passes immutable props only —
name="text" literals (ADR-0042) or one forwarded parent prop
name={prop} (ADR-0068); events and composed values stay inside the
child's own view
```

otherwise. The reason is chosen at macro time, where the shape is
visible; the spec check runs at term-elab time, where the spec is
visible. The error points at the head's own span (same position the
unknown-identifier error carried). Heads without a spec fall through
to `Term.elabTerm` of the identical application term the macro used
to emit, so the ADR-0039 surface is untouched — pinned by the
existing `<Metric value={metricValue}/>` test compiling unchanged.

Witnesses (both keep a checked `Chip` spec in scope, separating
LRX-ELAB-132 from LRX-ELAB-130's spec-less forwarding and from
LRX-ELAB-131's row-template rejection):

- `Test/fixtures/compile-fail/ChildRefWithChildren.lean` — the
  non-empty-children arm,
- `Test/fixtures/compile-fail/ChildRefComposedProp.lean` — the
  composed-value arm (`tag={heading ++ "!"}` against a declared
  parent prop `heading`, the exact ADR-0068 boundary),

both registered in `scripts/check_compile_fail.sh`.

The change is elaborator-only and error-path-only: no generated
module, manifest, or host byte moves.

## Consequences

- A misshapen reference to a checked component now names the
  composition contract instead of denying the component's existence;
  the `sorryAx` cascade behind the unknown identifier is gone with
  its cause.
- The full misuse boundary for a spec'd head is now: LRX-ELAB-112
  (right shape, wrong prop names/order — including sugared event
  refs), LRX-ELAB-130 (forwarding into a spec-less head),
  LRX-ELAB-131 (any head in a sealed row template), LRX-ELAB-132
  (spec'd head, shape outside the child-reference contract).
- OQ1: a *spec-less* head with non-empty children still silently
  drops them (`componentCall` never received children; pre-existing
  behavior preserved through the guard's fall-through). No live
  surface writes that shape; making it a diagnostic would touch the
  sealed ADR-0039 contract and deserves its own witness round.
- OQ2: the logical reference view's `componentCall` fallback is
  unchanged — logical views cannot nest checked components at all,
  and a spec'd head there still dies with the raw unknown-identifier
  error. Symmetric treatment is cheap if the logical surface ever
  grows a user beyond the differential tests.
