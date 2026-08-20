# LeanRx architecture guide

This page explains the implemented repository. `ARCHITECTURE.md` remains the
normative specification when prose here and code appear to disagree.

## Product thesis

LeanRx stages a small reactive language inside Lean. Lean's type checker protects
schemas, fields, dependent values, refinements, and proof-carrying planners. A
project-owned compiler lowers only recognized constructs into a validity-checked
JavaScript AST and a tiny direct-DOM runtime. Reactive discovery, `Proxy`,
`currentObserver`, `eval`, `Function`, raw HTML, and a root Virtual DOM are absent.

## Compiler flow

```text
Schema / Field / RuntimeType
           ↓
RxExpr Γ deps α + closed updates/views/commands
           ↓
ComponentSpec.check / specialized checked specification
           ↓
PlannedGraph + certified schedule + packed evaluator metadata
           ↓
Reactive IR / application-specific checked lowering
           ↓
validated Js.Module
           ↓
deterministic ESM + manifest + graph artifacts
           ↓
tiny explicit browser hosts
```

The pure input, graph, IR, AST, serializer, and planner phases perform no file or
browser IO. CLI/build boundaries stage complete output and publish a prepared
versioned sibling with one pointer replacement.

## Repository layers

| Layer | Main paths | Responsibility |
|---|---|---|
| Typed core | `LeanRx/Core` | schemas, fields, stores, dependency sets, runtime/equality evidence, staged expressions |
| Graph | `LeanRx/Graph` | checked node construction, diagnostics, schedules, JSON/DOT/HTML artifacts, all-Int proof bridge |
| Semantics | `LeanRx/Semantics` | reference and affected-frontier abstract execution |
| Proofs | `LeanRx/Proofs` | dependency, propagation, transaction, and selected structural correctness theorems |
| Component/view | `LeanRx/Component`, `LeanRx/View`, `LeanRx/Elab` | checked static component model and scoped syntax |
| IR/lowering | `LeanRx/IR`, `LeanRx/Lower` | typed reactive IR, proof erasure checks, staged scalar lowering |
| Backend | `LeanRx/Backend` | typed JavaScript AST/printer and controlled component/specialized emitters |
| Feature models | `LeanRx/Form`, `Region`, `Effect`, `Todo`, `Notes`, `IssueBrowser`, `Collection`, `Grid` | pure models and checked feature contracts |
| Host | `runtime/*.mjs` | direct DOM, disposal, local regions, owned effects, checked ports |
| Applications | `examples` | public-API dogfoods and atomic artifact builders |
| Verification | `Test`, `scripts`, `bench` | native/proof/policy/differential/browser/benchmark gates |

No source may skip from an application model to handwritten reactive JavaScript.
Specialized backends exist where general extraction is not implemented, and that
duplication is tested and documented as part of the TCB rather than called proved.

## Static graph and scheduling

Each checked node has a stable ID, unique name, kind, runtime type, complete
direct dependencies, source span, rank, equality metadata, and evaluator identity.
`Graph.plan` validates shape before constructing a private `PlannedGraph` with a
certified topological schedule. Cycles report a stable code, trimmed path, and
source spans.

M2's all-Int adapter derives the executable graph and homogeneous abstract
program from the same dependency-indexed expressions. The broader component
backend is executable checked lowering, not covered by that equivalence theorem.

## Transactions and actual change

Generated scalar components keep source state, derived caches, sink caches,
transaction depth, copied metrics, and trace state inside each mount closure.
Outermost commit compares the final source snapshot; only changed sources seed
the affected closure. Derived nodes run in schedule order, and lawful equality
stops propagation. Sinks evaluate when affected and call the DOM only when their
cached output changed. Disposal removes listeners and owned resources exactly
once; public instrumentation returns defensive copies.

The exact ten-slot metric contract and trace vocabulary are in
[`internals/transactions.md`](../internals/transactions.md).

## Direct DOM and local dynamic regions

Static components create their owned tree once and retain direct text/property
references. Dynamic shape is isolated behind conditional, positional, keyed, and
delta-keyed region capabilities. Region hosts own anchors and entries, validate
whole batches before mutation, move retained DOM instances locally, and dispose
removed subtrees. They are not a root renderer or dependency scheduler.

## Effects and foreign boundaries

Commands are values emitted after pure state update/render. The effect runtime
owns handle generations; replacement removes old ownership before cancellation,
stale completions must match their exact entry, and disposal clears ownership
before foreign callbacks. Timers, storage, HTTP, and ports normalize failures into
typed delivery. Issue decoding preserves JSON-number lexemes where JavaScript
`Number` would lose the native wire contract.

## Artifact contract

Every backend artifact is deterministic for a fixed source/toolchain. Manifests
record compiler/toolchain/runtime ABI, allocated export names, state-slot
representations, source/derived/sink/event counts, host imports, ports, graph hash,
and feature flags. Graphs are emitted as data JSON, DOT, and self-contained
script-free accessible HTML. Standalone JSON is not automatically safe for an
inline HTML `<script>` context; consumers must keep it as fetched data.

## Error and extension policy

Unsupported constructs fail with stable phase-prefixed diagnostics. New value,
DOM, event, region, or effect capabilities require:

1. a closed typed representation;
2. validation and source-linked diagnostics;
3. deterministic serialization/manifest disclosure;
4. native and generated agreement evidence where applicable;
5. hostile/error/cleanup tests at the new trust boundary;
6. an ABI/ADR update when a host contract changes.

The current support matrix is [documented separately](backend-support.md), and
the exact proof/TCB boundary is in the [trust model](trust-model.md).
