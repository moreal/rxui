# ADR-0023: Flatten the js-framework-benchmark application into one module at build time

- Status: Accepted
- Date: 2026-08-23

## Context

After ADR-0022 the js-framework-benchmark page fetched five files (`index.html`,
a two-line `main.mjs`, the generated module, the DOM host, the keyed region
host): 20,684 raw and 5,415 upstream-style Brotli bytes, against Solid's single
11,563-byte module that compresses to 4,358 bytes. Every upstream implementation
ships a production build (Solid's is Rollup plus Terser output), while LeanRx
shipped its repository hosts byte for byte, each compressed on its own and each
carrying documentation comments and indentation that compress poorly. The size
rows were the only upstream rows where LeanRx was clearly behind Solid; every
CPU row is at or below vanilla JavaScript's script time within noise, so the
remaining benchmark headroom is bytes and fetches. ADR-0021 and ADR-0022 left
two options undecided: a minifier (a new build dependency) or bundle-time
transformation of the hosts, both of which change the "shipped hosts are the
repository hosts" stance those records kept.

## Decision

`lake exe leanrx_js_framework_benchmark` writes one application module,
`main.mjs`, that contains, in this order: the hosts named by the generated
module's manifest `hostImports`, read from `runtime/` in import order and
inlined by dropping whole-line `//` comments, blank lines, leading indentation,
and the `export` keyword of their function declarations; the generated
declarations printed without their import and export statements (the host
names become free names of the module, which the JavaScript AST validator still
checks against every declaration, parameter, and local); and the mount
statement. The asset manifest lists `index.html` and `main.mjs`; the generated
manifest is written as `main.mjs.manifest.json` and still records the host
imports that were inlined. The build refuses a host that contains an `import`
or `export {` line, and the benchmark gate syntax-checks and runs the result.

Nothing else changes. Identifiers, statements, and line order inside the hosts
are kept, so a diff of the inlined host against `runtime/` shows only
whitespace, comments, and `export`; no function is tree-shaken, even the host
functions this application never calls; no minifier is added and the JavaScript
printer's compact mode is unchanged. The flattening is a property of this
production artifact only: every other example bundle keeps importing the
repository hosts as separate modules, the runtime ABI stays at 12, and the Lean
models and backends are untouched.

## Consequences

The benchmark application fetches two files instead of five and its local
baseline moves from 20,684 to 17,480 raw bytes and from 5,415 to 4,277
upstream-style Brotli bytes; the JavaScript alone (15,814 raw, 3,917 Brotli) is
now smaller than Solid's after compression and larger before it. The shipped
benchmark hosts are no longer the repository hosts byte for byte, which is why
this is a recorded decision rather than a build detail; the readable hosts in
`runtime/` remain the contract and the only thing `leanrx doctor` checks. A
minifier remains undecided: esbuild's bundle-and-minify of the same five files
measures about 3,100 Brotli bytes, so it is the next size step if one is
wanted, at the price of a build dependency and renamed identifiers.

## Validation

The benchmark gate (`scripts/check_js_framework_benchmark.sh`) syntax-checks
`main.mjs`, compares the size report with the recorded baseline, and runs the
three Playwright contract tests against a server that serves only `index.html`
and `main.mjs`; the Lean backend test still asserts the generated manifest; and
the upstream benchmark run records the result in `BENCHMARK.md`.
