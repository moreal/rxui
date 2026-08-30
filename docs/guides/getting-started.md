# Getting started

LeanRx is an unreleased Lean 4-hosted frontend compiler experiment. Work from
this checkout; there is no package URL or compatibility promise yet.

## 1. Diagnose the checkout

```sh
lake exe leanrx -- doctor
```

`doctor` checks the pinned Lean toolchain, Node, Corepack/pnpm, Tailwind,
Playwright, Chromium, the runtime hosts, and a pure backend smoke test. Fix
every reported error before treating browser output as reproducible.

## 2. Scaffold and type-check a component

```sh
lake exe leanrx -- scaffold --out .tmp/starter
lake env lean .tmp/starter/App.lean
```

The scaffold imports only the public `LeanRx` root. Its output path is an atomic
LeanRx-managed pointer: the first build requires an absent path, and later builds
replace only that managed pointer.

## 3. Check and inspect a registered component

```sh
lake exe leanrx -- check Examples.Counter
lake exe leanrx -- graph Examples.Counter --format html > .tmp/Counter.graph.html
```

`check` validates the staged component without writing files. `graph` exposes
stable nodes, dependencies, source spans, and the certified schedule as JSON,
DOT, or script-free HTML.

## 4. Build a browser bundle

```sh
lake exe leanrx -- build Examples.Counter --out .tmp/counter
```

Serve `.tmp/counter/index.html` from an HTTP server. Generated ESM imports a
small direct-DOM host; it does not contain a Lean runtime, Virtual DOM, runtime
observer, or arbitrary JavaScript evaluator.

## 5. Build the self-hosted docs dogfood

Install the pinned frontend tooling once, then build:

```sh
corepack pnpm install --frozen-lockfile --ignore-scripts
corepack pnpm docs:build -- .tmp/docs
```

The docs publisher compiles Tailwind inside the same staging directory as the
LeanRx module, graph artifacts, Markdown sources, and HTML shell. Publication
happens only after every artifact is ready.

## Before building a real application

Read the [language guide](language.md),
[backend support matrix](backend-support.md), and
[trust model](trust-model.md). A term that works in native Lean is not
automatically supported by the controlled browser backend.
