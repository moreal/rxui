# LeanRx tooling guide

All commands below run from this repository root. The compiler executable has an
explicit registry; it does not discover or dynamically load arbitrary Lean
modules.

## Fast feedback map

| Question | Cheapest command |
|---|---|
| Does this Lean/source surface elaborate? | `lake env lean path/to/File.lean` |
| Does a registered component and both JS printers validate? | `lake exe leanrx -- check MODULE` |
| Which node depends on this field? | `lake exe leanrx -- graph MODULE --format html` |
| What exactly ships? | `lake exe leanrx -- build MODULE --out DIRECTORY` |
| What does a stable public error mean? | `lake exe leanrx -- explain CODE` |
| Is the full checkout ready for browser evidence? | `lake exe leanrx -- doctor` |

`check`, `graph`, and `build` know only modules compiled into the driver's
registry. Use direct Lean checking and an application-specific builder while a
new component is not registered.

## Diagnose the checkout

```sh
lake exe leanrx -- doctor
```

`doctor` reports compiler version, exact Lean toolchain, runtime ABI, Node 22+,
exact Corepack/pnpm, Tailwind, and Playwright versions, installed Chromium,
required browser hosts, and a pure Counter backend smoke check. It returns
nonzero when a required item is unavailable or incompatible.

## Scaffold a public-API starter

```sh
lake exe leanrx -- scaffold --out .tmp/starter
lake env lean .tmp/starter/App.lean
```

Scaffold publication is atomic and refuses unmanaged output replacement. The
starter deliberately does not invent a remote package URL or license because
LeanRx is not released and this repository has no selected license.

## Check a registered component

```sh
lake exe leanrx -- check Examples.Counter
lake exe leanrx -- check Examples.LeanRxDocs
```

The command reports component name, graph/schedule size, source/derived counts,
text sinks/events, readable/compact backend validation, and a final result. It
does not write artifacts.

## Inspect a graph

```sh
lake exe leanrx -- graph Examples.Counter --format json
lake exe leanrx -- graph Examples.Counter --format dot
lake exe leanrx -- graph Examples.Counter --format html > Counter.graph.html
```

JSON is machine data, DOT carries detailed labels/source spans, and HTML is a
self-contained script-free accessible card view of nodes plus the certified
schedule. The HTML viewer is deterministic and safe as a standalone document;
JSON/DOT should still be handled in their own contexts.

## Build an atomic bundle

```sh
lake exe leanrx -- build Examples.Counter --out .tmp/counter
lake exe leanrx -- build Examples.LeanRxDocs --out .tmp/docs
```

The docs build additionally runs the pinned Tailwind v4 CLI inside the atomic
staging directory and publishes Markdown copies beside the generated app. The
equivalent package script is:

```sh
corepack pnpm docs:build -- .tmp/docs
```

The output path becomes a LeanRx-managed symbolic-link pointer to a complete
versioned sibling. First publication requires an absent path; later publication
accepts only the managed pointer. Generation, validation, and all writes finish
before the prepared pointer is renamed. Platform filesystem behavior remains in
the documented TCB; see [ADR-0007](../adr/0007-atomic-versioned-output.md).

Selected bundles contain a `.generated.lean` module that aliases inspectable
schema/declaration/spec/check names. Verify it with `lake env lean`.

The exact files are application-owned. The Counter bundle contains its ESM,
adjacent manifest, three graph formats, generated Lean aliases, and direct-DOM
host, but no `index.html`. The docs and js-framework-benchmark publishers are
full applications and do emit HTML shells. Do not assume every `build` result is
a directly navigable site; inspect the publisher or bundle contents.

Treat the output path as a read-only pointer after publication. Adding files
through it mutates the versioned directory but does not teach the next build
about those files; they disappear when the pointer advances. Put hand-authored
shells and deployment configuration outside the managed bundle, or make them
part of the application publisher.

## Publish the documentation site

The `Publish LeanRx docs and benchmark results` workflow deploys the generated
site to <https://moreal.github.io/rxui/>. Every push to `main` rebuilds the docs
and restores the latest successful benchmark under `/rxui/benchmark/`. The
three-hour schedule rebuilds both the docs and the upstream benchmark, so the
two Pages producers cannot overwrite each other.

Manual workflow dispatches restore the previous benchmark by default. Select
`refresh_benchmark` only when the approximately one-hour upstream comparison is
intended.

## Explain a diagnostic

```sh
lake exe leanrx -- explain LRX-GRAPH-001
lake exe leanrx -- explain LRX-TYPE-108
```

Explanations include phase, meaning, and next action for registered public codes.
Unknown codes fail rather than receiving a guessed explanation.

For an unregistered code, keep the original rendered message and source span.
The prefix still identifies the failing phase, but prose must not invent a
meaning that the checker did not report.

## Run examples directly

The repository exposes dedicated executables such as:

```sh
lake exe leanrx_expr_playground
lake exe leanrx_graph_lab
lake exe leanrx_counter_js -- .tmp/counter
lake exe leanrx_tabs_js -- .tmp/tabs
lake exe leanrx_todo_js -- .tmp/todo
lake exe leanrx_issue_browser_js -- .tmp/issues
lake exe leanrx_data_grid_js -- .tmp/grid
lake exe leanrx_docs_js -- .tmp/docs
```

See `lakefile.lean` for the exact list.

## Run verification gates

The complete local/CI suite is:

```sh
./scripts/check.sh
```

Its component commands are listed in the root `README.md`. Important focused
gates include:

- `lake exe leanrx_test`: native examples and exact environment audit;
- `lake exe leanrx_graph_properties -- 195936478`: replayable graph properties;
- `check_differential.sh`: native-to-JavaScript scalar vectors in both printers;
- `check_component_codegen.sh`: deterministic application artifacts and manifests;
- `check_region_runtime.sh`, `check_effect_runtime.sh`: fake-host adversarial gates;
- `check_browser.sh`: Chromium semantics, security, keyboard, axe, and disposal;
- the docs artifact/browser gates: Tailwind source detection, responsive layout,
  active navigation, Markdown export, and explicit shadcn compatibility metadata;
- `check_js_framework_benchmark.sh`: standard keyed-app contract and size baseline;
- `check_compile_fail.sh`: sealed public boundaries and source diagnostics;
- policy/audit scripts: placeholders, exact axioms, and semantic unsafe scope.

Browser tests require installed pinned dependencies and a permitted loopback test
server. No timing assertion is hidden inside the correctness suite. The M10
performance report and the
[js-framework-benchmark guide](../performance/js-framework-benchmark.md) provide
their separate measurement commands and caveats.

## Determinism and clean-checkout expectations

Artifact gates generate into two independent temporary directories and byte-diff
them. Release/handoff verification also runs `./scripts/check.sh` from a fresh
clone without hardlinks. A documented command must exist and work in the commit
that documents it; commits are expected to remain buildable and bisectable.

## Troubleshooting boundaries

- A successful `lake env lean` followed by `LRX-BE-*` is a backend support gap,
  not proof that the browser should accept the term.
- `LRX-ELAB-020` means the CLI registry lacks the requested name; it does not
  search the import graph.
- `LRX-PORT-003` protects an unmanaged output. Choose an absent path instead of
  deleting or overwriting data you have not identified.
- A browser gate that cannot bind `127.0.0.1` has not tested the application;
  rerun where loopback servers are permitted.
- Artifact diffs should be explained through graph, manifest, ABI, or printer
  changes. Regenerating expected bytes without understanding the delta weakens
  the determinism contract.
