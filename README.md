# LeanRx

LeanRx is a Lean 4-hosted frontend language and compiler experiment. It is being
implemented milestone by milestone against [ARCHITECTURE.md](ARCHITECTURE.md)
and [PLAN.md](PLAN.md). The repository is not yet a released framework.

## Prerequisites

- Elan with the toolchain named in `lean-toolchain` (Lean 4.33.0)
- Git
- Bash and ripgrep for repository policy gates
- POSIX `ln` and `readlink` for atomic versioned-directory publication
- Node.js 22 or newer for M3 generated-module differential tests
- Corepack with pnpm 10.33.0 (pinned by `packageManager`) for browser tests

## Reproducible commands

```sh
./scripts/check_format.sh
lake build
lake exe leanrx_test
lake exe leanrx_graph_properties -- 195936478
./scripts/check_differential.sh
./scripts/check_component_codegen.sh
./scripts/check_region_runtime.sh
./scripts/check_effect_runtime.sh
./scripts/check_cli.sh
./scripts/check_browser.sh
./scripts/check_bench.sh
./scripts/check_grid_bench.sh
./scripts/check_examples.sh
./scripts/check_compile_fail.sh
./scripts/check_placeholders.sh
./scripts/test_placeholder_scanner.sh
./scripts/check_axioms.sh
./scripts/check_semantic_safety.sh
```

The same commands run in CI. See [STATUS.md](STATUS.md) for the current
milestone, exact baseline, and the latest green commit.

New readers should start with the [documentation index](docs/README.md), then the
[language guide](docs/guides/language.md) and
[tooling guide](docs/guides/tooling.md). The
[backend matrix](docs/guides/backend-support.md) distinguishes native Lean code
from constructs the controlled browser backend actually supports.

Install the exact browser-test dependencies and Chromium once before running the
browser gate:

```sh
corepack pnpm install --frozen-lockfile --ignore-scripts
corepack pnpm exec playwright install chromium
```

Run the M1 public-API dogfood directly with:

```sh
lake exe leanrx_expr_playground
```

Run the M2 graph/proof dogfood and replayable property suite with:

```sh
lake exe leanrx_graph_lab
lake exe leanrx_graph_properties -- 195936478
```

Run the M3 deterministic scalar JavaScript differential and generated Expression
Playground gates with:

```sh
./scripts/check_differential.sh
./scripts/check_examples.sh
```

Generate the explicit M4 Counter component, graph, runtime host, and manifest:

```sh
lake exe leanrx_counter_js -- .tmp/counter
lake exe leanrx -- check Examples.Counter
lake exe leanrx -- graph Examples.Counter --format json
lake exe leanrx -- graph Examples.Counter --format dot
lake exe leanrx -- build Examples.Counter --out .tmp/counter
```

`build` publishes a complete versioned sibling directory by atomically replacing
the output path's symbolic-link pointer. The first output path must be absent;
later builds must target the LeanRx-managed pointer. An existing unmanaged file
or real directory is rejected without modification because POSIX cannot replace
a nonempty directory atomically. See [ADR-0007](docs/adr/0007-atomic-versioned-output.md).

The M4 syntax is opt-in so its declaration keywords do not pollute ordinary Lean:

```lean
open scoped LeanRxDsl
```

Counter demonstrates the balanced JSX-like child-list form and inspectable
generated declarations. See [ADR-0006](docs/adr/0006-scoped-component-jsx-syntax.md)
for the parser rationale and complete example.

M5 transaction depth, affected-frontier scheduling, counters, trace names, and
the current derived-read restriction are documented in
[the transaction contract](docs/internals/transactions.md). Diamond Lab runs the
fan-in browser scenario through `./scripts/check_browser.sh`.

Generate the M6 dependent-type dogfood with:

```sh
lake exe leanrx_tabs_js -- .tmp/tabs
```

Dependent Tabs accepts equal nonempty `Vector` props, stores selection and event
payloads as `Fin`, lowers safe access to one array index, and emits no proof
objects. Nonzero initial selection uses `TabsSpec.createAt index proof`; raw Lean
numeric `Fin` literals are deliberately excluded from that public boundary
because pinned Lean normalizes them modulo. See
[ADR-0011](docs/adr/0011-fin-literal-normalization.md) and the
[runtime representation contract](docs/internals/runtime-representation.md).

Generate the M7 controlled-input dogfood applications with:

```sh
lake exe leanrx_temperature_js -- .tmp/temperature
lake exe leanrx_validated_form_js -- .tmp/validated-form
```

Temperature Converter preserves invalid raw edits and cursor position while
updating the opposite field only after an explicit integer parse. Validated Form
uses nonempty/bounded/accepted refinements, checked and disabled properties,
prevented submit, and a fake command that only `ValidatedForm` can construct.
The pure/native, generated-JavaScript, remaining-TCB, and accessibility contracts
are documented in [the form internals](docs/internals/forms.md).

Generate the M8 keyed TodoMVC dogfood application with:

```sh
lake exe leanrx_todo_js -- .tmp/todo
```

TodoMVC uses a pure closed update model and generated direct DOM outside three
explicit local region kinds: conditional edit/view branches, positional filter
controls, and keyed rows. Key identity survives reorder, stable rows update in
place, removed rows dispose their nested branch, and no root-wide Virtual DOM is
present. See [the dynamic-region contract](docs/internals/dynamic-regions.md).

Generate the M9 effect dogfoods with:

```sh
lake exe leanrx_notes_js -- .tmp/notes
lake exe leanrx_issue_browser_js -- .tmp/issues
```

Notes owns storage restore, a replaceable debounce timer, persistence errors,
and disposal cancellation. Issue Browser owns HTTP requests, typed decode,
loading/failure/success resource state, pagination, retry, stale-result
suppression, and abort-on-replacement/disposal. Foreign ports disclose their
wire types, errors, trust, and security contracts in deterministic manifests.
See [the effects and ports contract](docs/internals/effects.md) and
[ADR-0015](docs/adr/0015-runtime-abi-v6-owned-effects.md).

The checked structural-delta region capability is versioned separately in
[ADR-0016](docs/adr/0016-runtime-abi-v7-structural-deltas.md); it leaves the
ten-slot transaction/effect instrumentation unchanged.

Generate and benchmark the public M10 Data Grid experiment with:

```sh
lake exe leanrx_data_grid_js -- .tmp/grid
./scripts/check_grid_bench.sh
```

The application compares full keyed recomputation, explicit checked deltas, and
an explicit-cost-model hybrid on the same 10,000-row trace. Measurements support
keeping delta opt-in rather than making it a default language feature; see the
[performance report](docs/performance/m10-data-grid.md) and
[ADR-0017](docs/adr/0017-structural-delta-remains-opt-in.md).

M11 adds learnability commands and a self-hosted documentation dogfood:

```sh
lake exe leanrx -- doctor
lake exe leanrx -- scaffold --out .tmp/starter
lake exe leanrx -- explain LRX-GRAPH-001
lake exe leanrx -- graph Examples.Counter --format html > .tmp/Counter.graph.html
lake exe leanrx -- build Examples.LeanRxDocs --out .tmp/docs
```

The seven-page site uses LeanRx state, derived values, events, text sinks, graphs,
and atomic output. It records rather than hides missing routing, semantic content
tags, typed CSS, SSR, and hydration. See the
[case studies](docs/guides/dogfood-case-studies.md),
[accessibility guide](docs/guides/accessibility.md), and
[trust model](docs/guides/trust-model.md).

## Project boundaries

LeanRx is intended to compile a restricted staged language; it will not transpile
arbitrary Lean. Unsupported browser constructs will be build errors. The intended backend
is a project-owned Reactive IR and typed JavaScript AST, with a small direct-DOM
host. Formal claims are limited to the pure Lean semantics and explicitly proved
theorems. For the finite abstract M2 model, Lean proves optimized final stores and
sink observations equal full recomputation under the documented well-formedness,
dependency, cache, and transaction hypotheses. Generated JavaScript and browser
behavior remain in the documented
trusted computing base.

M2's `Graph.planInt` adapter derives graph metadata and the homogeneous proof
program from the same dependency-indexed `RxExpr` declarations. It is the checked
proof-subset bridge; broader heterogeneous component extraction is not claimed yet.

No project license has been selected. `NOTICE.md` records prior-art provenance;
it does not grant a license to this repository.
