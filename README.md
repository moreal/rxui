# LeanRx

LeanRx is a Lean 4-hosted frontend language and compiler experiment. It is being
implemented milestone by milestone against [ARCHITECTURE.md](ARCHITECTURE.md)
and [PLAN.md](PLAN.md). The repository is not yet a released framework.

## Prerequisites

- Elan with the toolchain named in `lean-toolchain` (Lean 4.33.0)
- Git
- Bash and ripgrep for repository policy gates
- Node.js 22 or newer for M3 generated-module differential tests
- pnpm will be introduced when browser tooling first requires it

## Reproducible commands

```sh
./scripts/check_format.sh
lake build
lake exe leanrx_test
lake exe leanrx_graph_properties -- 195936478
./scripts/check_differential.sh
./scripts/check_component_codegen.sh
./scripts/check_browser.sh
./scripts/check_examples.sh
./scripts/check_compile_fail.sh
./scripts/check_placeholders.sh
./scripts/test_placeholder_scanner.sh
./scripts/check_axioms.sh
./scripts/check_semantic_safety.sh
```

The same commands run in CI. See [STATUS.md](STATUS.md) for the current
milestone, exact baseline, and the latest green commit.

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
```

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
