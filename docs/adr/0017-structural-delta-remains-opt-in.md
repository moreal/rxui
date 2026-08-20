# ADR-0017: Keep structural delta opt-in

- Status: Accepted
- Date: 2026-08-21

## Context

The M10 experiment implements and checks three variants of the same 10,000-row
application: full keyed recomputation, explicit `ListDelta`, and a hybrid with an
explicit cost model. The architecture requires a data-driven decision rather
than assuming that incremental structural work is always cheaper.

## Decision

Structural delta remains an opt-in experimental library. Full keyed collection
recomputation remains the default dynamic-region behavior. A specialized checked
backend may select explicit delta or hybrid behavior, but must disclose that
feature in its manifest and supply a concrete cost model and measurements. The
M10 generated component deliberately fixes that model to the checked default;
the pure reference runner remains configurable for research without silently
expanding the browser contract.

`ListDelta.applyAll` and private-constructor `PlannedDeltas` remain public
building blocks. A candidate batch is accepted only when checked application
equals the independently recomputed target; otherwise the planner visibly falls
back to `reset`. This does not add implicit delta propagation to scalar graphs or
move strategy selection into the browser host.

## Evidence

The complete measurements are in
[`docs/performance/m10-data-grid.md`](../performance/m10-data-grid.md). In the
defining browser trace, delta/hybrid reduce standard sink evaluations from
43,007 to 10,009/19,009 and retained updates from 43,000 to
10,002/19,002. They substantially improve one-row update and two-row reorder
medians. Standard emitted DOM writes remain exactly 40,009 for every strategy;
all variants create and reach the same changed DOM. Explicit delta is slower for
the 1,000-row removal and does not improve filtering or sorting. Five native
samples show no meaningful end-to-end timing separation. Chromium allocation
sampling distinguishes executed samples but remains statistical and includes
browser assertion work; process-wide heap size does not distinguish strategies.

The experiment also adds substantial proof, runtime, specialized-backend, test,
and API surface. Composed delta operators such as map/filter/key/sort still need
their own full-recomputation correctness statements.

## Consequences

No ordinary LeanRx application must understand structural deltas, and the static
scalar path is unchanged. The opt-in library and ABI-7 host remain supported by
native correctness, deterministic work-count, fake-DOM, artifact, and Chromium
gates. Generated JavaScript, strategy lowering, the region host, DOM, browser,
timing, memory reporting, and cost-model fit remain inside the trusted computing
base or empirical evidence boundary rather than the formal claim.

Core-language promotion requires broader browser/device/data-shape benchmarks,
isolated application allocation profiling and bundle-size comparison,
composed-operator proofs, and a generated-work-aware cost model.
