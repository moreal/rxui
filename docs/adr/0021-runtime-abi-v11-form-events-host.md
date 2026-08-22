# ADR-0021: Bump the internal runtime ABI for a separate form-event host

- Status: Accepted
- Date: 2026-08-23

## Context

Since ADR-0013 the DOM host `runtime/leanrx_dom.mjs` has carried the five typed
control-event adapters (`listenValue`, `listenChecked`, `listenKey`,
`listenFocus`, `listenSubmit`) next to node construction, traversal, mutation,
the generic `listen`, and the delegated-event adapter (`setKey`,
`listenDelegated`). Artifacts that receive every event through delegation (the
js-framework-benchmark table and the Data Grid) therefore ship about 1.2 KB of
adapters they never import, and after ADR-0019/ADR-0020 moved the optional
region kinds into their own hosts, these adapters were the last host code the
benchmark fetched without using. The size rows of the upstream benchmark are
the only rows where LeanRx is clearly behind Solid (22.7 KB against 11.5 KB
uncompressed); every CPU row is at or below vanilla JavaScript's script time
within noise. None of this involves the checked Lean models; the form backends,
their `ControlEvent`/`DomProperty` lowering, and the adapters' behavior are
unchanged.

## Decision

The internal JavaScript runtime ABI becomes version 11 for every artifact.

`listenValue`, `listenChecked`, `listenKey`, `listenFocus`, and `listenSubmit`
move, byte for byte, from `runtime/leanrx_dom.mjs` to a new host module
`runtime/leanrx_form_events.mjs`. The DOM host keeps node construction,
traversal, mutation, `setProperty`, `uniqueId`, the generic `listen`, and the
delegated-event adapter (`setKey`, `listenDelegated`), because template-cloned
keyed rows depend on `setKey` and `listenDelegated` together. Backends that
lower a `ControlEvent` (Temperature, Validated Form, Notes, TodoMVC, Issue
Browser) import the adapters from the new module and list it in their manifest
`hostImports`; their example builds copy it, `leanrx doctor` checks for it, and
the component-codegen gate syntax-checks it. Artifacts that use `listen` or
`listenDelegated` only (Counter, Diamond, Tabs, Docs, Data Grid, the
js-framework-benchmark) keep their host imports and ship the smaller DOM host.

## Consequences

ABI-10 and ABI-11 artifacts/hosts must not be mixed. All manifests move to
version 11. The five form artifacts fetch one more module (in parallel with the
DOM host, so no additional serial round trip) for the same bytes; the
delegated-only artifacts ship 1,214 fewer raw bytes (the js-framework-benchmark
baseline moves from 23,261 to 22,047 raw bytes and from 6,506 to 6,422
upstream-style Brotli bytes). The host surface and every adapter contract are
unchanged; ADR-0013 remains the decision record for the adapters' behavior.
Further size reductions would need either a minifier (a new build dependency)
or stripping host documentation comments at bundle time, both of which change
the "shipped hosts are the repository hosts" stance and are not decided here.

## Validation

The existing browser gates for Temperature, Validated Form, Notes, TodoMVC, and
Issue Browser run against the split hosts; the Node artifact checks assert the
new `hostImports` (and the ABI literal) for every artifact; the deterministic
codegen gate diffs two builds and syntax-checks the new host; the
js-framework-benchmark size gate records the new baseline; and the upstream
benchmark run records the result in `BENCHMARK.md`.
