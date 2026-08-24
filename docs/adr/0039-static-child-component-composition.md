# ADR-0039: Compose stateful child components by static module import

- Status: Accepted
- Date: 2026-08-25

## Context

Every checked component compiled to exactly one module with one `mount`
export; a view could not contain another component. PLAN.md M8 anticipates
"child component ownership", and the component sugar (ADR-0036) already
parses `<Child/>` heads — but only as ordinary term application of a view
template function, which cannot own state. Three designs were on the table
for the first stateful step: schema joining (embed the child's fields into
the parent schema and check one composite `ComponentSpec`), backend inlining
(emit the child's evaluators and shell into the parent module under a name
prefix), and module-level composition (the parent imports the child's
generated module).

## Decision

Phase 1 is module-level static composition with fully independent state:

- Schema joining is deliberately deferred. Joining would break the
  sources-form-a-leading-prefix invariant (LRX-TYPE-105) without a
  permutation layer over every `Field`/`DepSet` index, and phase 1 has no
  parent↔child data flow to pay for it. Parent and child keep separate
  schemas, state arrays, transactions, and instrumentation.
- The view model gains `View.child (name)`: inside a `component` block, an
  attr-less, child-less capitalized element (`<Pulse/>`) lowers to
  `View.child "Pulse"` exactly when `Pulse_spec` — the `component` command's
  generated specification — resolves in scope; otherwise the head keeps its
  existing term-application meaning. The command records each such head in
  the new `ComponentSpec.children` table (`ChildComponent.of name`, module
  specifier `./{name}.mjs` by convention). Validation requires every view
  reference to name a declared child (`LRX-VIEW-023`) and the table to hold
  unique names with same-directory `.mjs` specifiers (`LRX-VIEW-024`).
- The parent module imports `mount as $lrx_child_{i}` from each child's
  module and calls it mid-mount at the child's position: `mount(parent)`
  appends the child root right there, so document order is preserved without
  a wrapper element. A child cannot be the view root (`LRX-BE-030`). The
  returned child disposer joins the parent's disposer list, so parent
  disposal detaches the child's listeners and DOM idempotently.
- Event namespacing needs no mangling in this design: generated dispatch
  functions are module-scoped, so parent and child event tables can share
  names freely. Manifests disclose composition instead — the child module
  specifier joins `hostImports` and the parent gains the `child-components`
  feature flag. The manifest counts (state slots, events, sinks) stay
  parent-only.

Later phases can layer parent→child inputs through `ImmutableProp` mount
arguments and child→parent events through a callback parameter on the child's
`mount` ABI without changing this composition boundary; spec-level inlining
remains available behind the same `View.child` surface if cross-module
imports ever become a deployment problem.

## Consequences

- `examples/NestLab.lean` dogfoods the surface: `NestLab` nests `<Pulse/>`,
  both components emitted side by side by `leanrx_nest_js`.
  `Test/browser/nest.spec.mjs` gates in-order mounting, state independence,
  and child disposal in Chromium; `Test/js/nest_artifacts.mjs` pins the
  import, the mid-mount call, the merged disposer list, and both manifests.
- Components without children emit byte-identical modules and manifests; the
  runtime ABI stays 15 (child mounting uses only the ESM import graph).
- The child's instrumentation is not reachable through the parent disposer
  in phase 1; a composed-instrumentation surface is future work.
- A `<Child/>` whose `Child_spec` is not in scope still elaborates as a term
  application, so template-function views keep working unchanged.
