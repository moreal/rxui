# Dogfood log

## M0 tooling smoke

### Scenario exercised

Pinned-toolchain Lake build and a public-library import from the native test
executable.

### What was pleasant

The required Lean 4.33.0 toolchain was already present, so the baseline required
no network fetch and produced a small dependency-free manifest.

### Friction

A module documentation comment cannot directly annotate a namespace in Lean
4.33.0; using a module comment fixed the root module cleanly. pnpm is not
available, but JavaScript tooling is intentionally deferred until M3.

### Missing framework capability

All user-facing framework capabilities are intentionally absent in M0.

### Bugs found

The initial root comment form caused a parser error. It was corrected before the
bootstrap commit; the native smoke executable covers import and version access.

### Performance observations

The dependency-free clean build completed in under three seconds on the baseline
machine. This is a tooling observation, not a framework benchmark.

### Follow-up issue or commit

`14d44a6 chore(repo): initialize LeanRx Lake package`

## Expression Playground

### Scenario exercised

Typed `price`, `quantity`, and `threshold` fields; staged `subtotal`, `isLarge`,
and conditional `label` expressions; dependency inspection; and native evaluation
against two heterogeneous stores.

### What was pleasant

Typed field witnesses make cross-typed reads unrepresentable, and expression
dependencies are inspectable through the same public values used for evaluation.
The output is deterministic enough to gate as a small golden fixture.

### Friction

The explicit combinators are intentionally verbose. There is no local staged
`let` or operator notation yet, so nested arithmetic is noisier than ordinary Lean.

### Missing framework capability

No source syntax, components, updates, graph extraction, or browser lowering is
expected in M1. Formatting values into staged strings is still primitive.

### Bugs found

Generalizing schema/store universes exposed several accidentally universe-zero
helper signatures; store integration tests forced those signatures to be fixed.

### Performance observations

The playground performs full pure evaluation. Runtime propagation work reduction
is an M2/M5 measurement and is not claimed here.

### Follow-up issue or commit

`example(expr): dogfood the scalar expression core`

## Graph Lab

### Scenario exercised

A public-API diamond graph with stable IDs, direct edges, certified topological
ranks, full-recomputation and actual-change evaluation, plus the required parity
case where `count` changes from 1 to 3 while `parity` remains odd.

### What was pleasant

Graph planning, deterministic artifact generation, reference evaluation, and
optimized evaluation are independently callable pure APIs. The diamond output is
compact enough for an exact golden, and the parity case makes work suppression
visible without browser instrumentation.

### Friction

The first Graph Lab version declared executable graph metadata and homogeneous
proof evaluators separately. Independent M2 review rejected that drift risk. The
all-`Int` proof subset now declares staged `RxExpr` values once and derives both
the planned graph and abstract program through `Graph.planInt`; general
heterogeneous component extraction remains future work.

### Missing framework capability

There is no source component syntax, automatic graph extraction from `RxExpr`,
JavaScript lowering, browser host, or DOM sink yet. Those begin in M3–M5.

### Bugs found

The first fixture review showed that graph validation allowed another node to
depend on a sink. `LRX-GRAPH-012` now rejects that invalid scalar-graph shape, and
the case is a permanent regression test. A later review found that validated
planned graphs were forgeable and Graph Lab duplicated its semantic program;
private planned constructors, a checked typed bridge, and compile-fail/connection
tests now cover both defects.

### Performance observations

For `count 1 → 3`, full recomputation performs two derived and two sink
evaluations. Actual-change propagation evaluates parity once and performs no
downstream or sink work: four evaluations versus one. This is deterministic work
instrumentation, not a wall-clock benchmark.

### Follow-up issue or commit

`example(graph): add native propagation laboratory`

## Expression Playground — generated ESM

### Scenario exercised

The existing public `subtotal`, `isLarge`, and conditional `label` expressions
are compiled through `RxExpr → Reactive IR → validated JavaScript AST → ESM`,
imported under Node, and compared with native Lean results for both playground
stores.

### What was pleasant

The compiler phases remain independently callable pure functions. The example
generator performs only file orchestration, and the Node runner needs no Lean
runtime or third-party package. Each module now carries deterministic ABI metadata
that the public dogfood reads and checks before execution.

### Friction

M3 has no component command or build CLI yet, so the dogfood uses a test-only
output-directory harness. Each generated evaluator currently accepts the whole
schema parameter list, including fields that a particular expression does not
read; later lowering can specialize parameters from the dependency index.

### Missing framework capability

There is still no DOM, event, component, or browser host output. The ESM functions
are pure scalar evaluators only, as required for M3.

### Bugs found

The differential gate found that the first `Int.mod` helper normalized with the
signed divisor. For `7 % -5`, Lean returned `2` while generated JavaScript returned
`-3`. The helper now normalizes with the absolute divisor, and all signed/zero
cases are permanent regressions. Independent review also found missing strict-ESM
identifier exclusions, shallow AST binding validation, and an untyped IR input
boundary; hostile-name Node imports, negative AST fixtures, and signature mismatch
tests now preserve those fixes.

### Performance observations

The gate records deterministic bytes and semantic results, not wall-clock
performance. No benchmark claim is made before the correctness baseline closes.

### Follow-up issue or commit

`example(js): emit and run the expression playground`
