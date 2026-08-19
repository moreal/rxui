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
./scripts/check_cli.sh
./scripts/check_browser.sh
./scripts/check_bench.sh
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
