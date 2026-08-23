# ADR-0022: Bump the internal runtime ABI to ship the disposer in the DOM host

- Status: Accepted
- Date: 2026-08-23

## Context

Since ADR-0008 every artifact has imported `makeDisposer` from its own host
module, `runtime/leanrx_host.mjs` (867 bytes, 28 lines), next to the DOM host
that the same artifact always imports. The pinned upstream
js-framework-benchmark server (`chrome150`) leaves responses below 1 KiB
uncompressed, so that module was the one shipped file that never compressed:
after ADR-0021 it was 867 of the application's 6,422 upstream-style Brotli
bytes (13.5%) and one of six fetched resources, while the same function
appended to the DOM host would compress with it. Separately, the keyed region
host `runtime/leanrx_region.mjs` had accumulated multi-line documentation
comments during ADR-0018/0019/0020 (33 comment lines; every other host has
between zero and eight), and prose compresses poorly: those comments were about
800 Brotli bytes of the 2,529-byte region host. The size rows remain the only
upstream rows where LeanRx is clearly behind Solid (21.5 KB against 11.5 KB
uncompressed, 6.3 against 4.5 KB Brotli); every CPU row is at or below vanilla
JavaScript's script time within noise. None of this involves the checked Lean
models; the backends' lowering and the hosts' behavior are unchanged.

## Decision

The internal JavaScript runtime ABI becomes version 12 for every artifact.

`makeDisposer` moves, byte for byte, from `runtime/leanrx_host.mjs` to the end
of `runtime/leanrx_dom.mjs`, and `runtime/leanrx_host.mjs` is deleted. Every
backend imports `makeDisposer` from the DOM host in the same import statement as
its node helpers and drops `./leanrx_host.mjs` from its manifest `hostImports`;
the example builds stop copying it, the browser specs stop serving it, `leanrx
doctor` stops checking for it, and the benchmark asset manifest lists five
files instead of six.

The region host and the DOM host keep the terse one- to three-line comments
the other hosts use. The longer contract prose (minimal keyed placement, the
owned-parent rebuild, the `update`/`updateAt` contract and its validation
order) moves to `docs/internals/runtime-representation.md`, which was already
the reference for the region ABI; the shipped hosts remain the repository's
host files unchanged by any bundle-time transformation, so the "shipped hosts
are the repository hosts" stance of ADR-0021 is kept. A minifier or bundle-time
comment stripping is still not adopted.

## Consequences

ABI-11 and ABI-12 artifacts/hosts must not be mixed. All manifests move to
version 12. Every artifact fetches one module fewer and ships about 600 fewer
Brotli bytes for the disposer; artifacts that import the keyed region host ship
about 320 fewer Brotli bytes for its comments. The js-framework-benchmark
baseline moves from 22,047 to 20,684 raw bytes and from 6,422 to 5,415
upstream-style Brotli bytes. `Test/js/region_runtime.mjs` imports
`makeDisposer` from the DOM host (whose functions touch `document` only when
called, so Node imports it without a DOM). The disposer's contract (idempotent
disposal, copied ten-slot instrumentation, region and grid instrumentation
accessors) is unchanged; ADR-0008 and ADR-0015 remain its decision records.

## Validation

The Node artifact checks assert the new `hostImports` and the ABI literal for
every artifact; the Lean backend tests assert the manifests; the browser gates
for Counter, Diamond, Tabs, Temperature, Validated Form, TodoMVC, Notes, Issue
Browser, Data Grid, Docs, and the js-framework-benchmark run against the merged
host; the deterministic codegen gate diffs two builds; the region-runtime gate
runs the fake-DOM suite against the merged import; the js-framework-benchmark
size gate records the new baseline; and the upstream benchmark run records the
result in `BENCHMARK.md`.
