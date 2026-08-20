# LeanRx tooling guide

All commands below run from this repository root. The compiler executable has an
explicit registry; it does not discover or dynamically load arbitrary Lean
modules.

## Diagnose the checkout

```sh
lake exe leanrx -- doctor
```

`doctor` reports compiler version, exact Lean toolchain, runtime ABI, Node 22+,
exact Corepack/pnpm and Playwright versions, installed Chromium, required browser
hosts, and a pure Counter backend smoke check. It returns nonzero when a required
item is unavailable or incompatible.

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

The output path becomes a LeanRx-managed symbolic-link pointer to a complete
versioned sibling. First publication requires an absent path; later publication
accepts only the managed pointer. Generation, validation, and all writes finish
before the prepared pointer is renamed. Platform filesystem behavior remains in
the documented TCB; see [ADR-0007](../adr/0007-atomic-versioned-output.md).

Selected bundles contain a `.generated.lean` module that aliases inspectable
schema/declaration/spec/check names. Verify it with `lake env lean`.

## Explain a diagnostic

```sh
lake exe leanrx -- explain LRX-GRAPH-001
lake exe leanrx -- explain LRX-TYPE-108
```

Explanations include phase, meaning, and next action for registered public codes.
Unknown codes fail rather than receiving a guessed explanation.

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
- `check_compile_fail.sh`: sealed public boundaries and source diagnostics;
- policy/audit scripts: placeholders, exact axioms, and semantic unsafe scope.

Browser tests require installed pinned dependencies and a permitted loopback test
server. No timing assertion is hidden inside the correctness suite. The M10
performance report provides its separate measurement commands and caveats.

## Determinism and clean-checkout expectations

Artifact gates generate into two independent temporary directories and byte-diff
them. Release/handoff verification also runs `./scripts/check.sh` from a fresh
clone without hardlinks. A documented command must exist and work in the commit
that documents it; commits are expected to remain buildable and bisectable.
