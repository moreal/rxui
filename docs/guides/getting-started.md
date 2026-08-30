# Getting started

LeanRx is an unreleased Lean 4-hosted frontend compiler experiment. Work from
this checkout; there is no package URL or compatibility promise yet.

At the end of this guide you will have a type-checked starter, an inspected
reactive graph, and a deterministic Counter component bundle. Commands run from
the repository root and use the exact toolchain in `lean-toolchain`.

## 1. Diagnose the checkout

```sh
lake exe leanrx -- doctor
```

`doctor` checks the pinned Lean toolchain, Node, Corepack/pnpm, Tailwind,
Playwright, Chromium, the runtime hosts, and a pure backend smoke test. Fix
every reported error before treating browser output as reproducible.

A successful run ends with `result: ready`. `doctor` is intentionally broader
than the minimum required to type-check `App.lean`: missing Chromium may block
browser evidence while Lean compilation itself still works.

## 2. Scaffold and type-check a component

```sh
lake exe leanrx -- scaffold --out .tmp/starter
lake env lean .tmp/starter/App.lean
```

The scaffold imports only the public `LeanRx` root. Its output path is an atomic
LeanRx-managed pointer: the first build requires an absent path, and later builds
replace only that managed pointer.

Inspect `.tmp/starter/App.lean`, then copy it into a project-owned source path
before changing it. The scaffold output is a replaceable managed bundle, not a
working directory. The file shows the explicit API in dependency order: schema
and typed field, staged expression, event, safe view, component specification,
then `spec.check`. `lake env lean` checks those layers without generating browser
files. For the more concise `component`/`rx%`/`jsx%` surface, continue with
[Writing components](components.md).

## 3. Check and inspect a registered component

```sh
lake exe leanrx -- check Examples.Counter
lake exe leanrx -- graph Examples.Counter --format html > .tmp/Counter.graph.html
```

`check` validates the staged component without writing files. `graph` exposes
stable nodes, dependencies, source spans, and the certified schedule as JSON,
DOT, or script-free HTML.

The repository CLI uses an explicit registry. `Examples.Counter` and
`Examples.LeanRxDocs` are registered; a newly scaffolded `LeanRxStarter` module
is not. Type-check a new module with `lake env lean` first, then add a
project-specific builder or deliberately extend the driver registry. An
`LRX-ELAB-020` response is a registry error, not a Lean import-discovery failure.

## 4. Build a browser bundle

```sh
lake exe leanrx -- build Examples.Counter --out .tmp/counter
```

The Counter publisher emits a component bundle, not an application HTML shell:

| Artifact | Purpose |
|---|---|
| `Counter.mjs` | validated ESM exporting `mount` |
| `leanrx_dom.mjs` | small direct-DOM host imported by the component |
| `Counter.mjs.manifest.json` | exact compiler, ABI, graph, representation, import, and feature metadata |
| `Counter.graph.{json,dot,html}` | machine, Graphviz, and script-free human graph views |
| `Counter.generated.lean` | editor-facing aliases for generated declarations |

There is deliberately no `.tmp/counter/index.html`. A browser application must
provide an HTML element and import the generated module, for example:

```html
<div id="app"></div>
<script type="module">
  import { mount } from "./counter/Counter.mjs";
  const dispose = mount(document.getElementById("app"));
  globalThis.addEventListener("pagehide", dispose, { once: true });
</script>
```

Save that shell beside the `counter` pointer (for example as
`.tmp/counter-host.html`) and serve `.tmp` over HTTP; module imports should not
be tested through `file:` URLs. The generated ESM contains no Lean runtime,
Virtual DOM, runtime observer, or arbitrary JavaScript evaluator. Do not add
files through the managed `.tmp/counter` pointer: a later atomic publication
replaces the complete bundle.

## 5. Build the self-hosted docs dogfood

Install the pinned frontend tooling once, then build:

```sh
corepack pnpm install --frozen-lockfile --ignore-scripts
corepack pnpm docs:build -- .tmp/docs
```

The docs publisher compiles Tailwind inside the same staging directory as the
LeanRx module, graph artifacts, Markdown sources, and HTML shell. Publication
happens only after every artifact is ready.

Unlike the Counter component publisher, this application publisher does own an
`index.html`, so `.tmp/docs/index.html` is a complete site entry point.

## A practical edit loop

For ordinary authoring, keep feedback narrow until the browser boundary changes:

1. run `lake env lean path/to/Component.lean` after schema or surface edits;
2. run `leanrx check` when the component is registered and backend lowering matters;
3. inspect `leanrx graph` after dependency or transaction changes;
4. build twice only when artifact determinism or publication behavior matters;
5. run the focused native/browser gate for the capability you changed, then the
   complete suite before handoff.

## Common first failures

| Symptom | Meaning | Next action |
|---|---|---|
| `LRX-RX-001` | a leaf inside `rx%` is outside the staged value vocabulary | use a schema field, staged expression, or supported literal/primitive |
| `LRX-TYPE-108` | an event tries to read a derived value before a supported barrier | read sources in the event or keep the computation derived |
| `LRX-ELAB-020` | the CLI executable has not registered that module | type-check directly or extend the explicit registry |
| `LRX-BE-020` | valid Lean reached a construct the controlled backend cannot lower | rewrite using the support matrix or implement a checked lowering |
| `LRX-PORT-003` | the output path is an unmanaged file or real directory | choose an absent path; never delete an unknown path just to satisfy the publisher |

Use `lake exe leanrx -- explain CODE` for registered public diagnostic codes.

## Before building a real application

Read the [language guide](language.md),
[backend support matrix](backend-support.md), and
[trust model](trust-model.md). A term that works in native Lean is not
automatically supported by the controlled browser backend.
