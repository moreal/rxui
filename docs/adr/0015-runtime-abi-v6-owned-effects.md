# ADR-0015: Bump the internal runtime ABI for owned effects

- Status: Accepted
- Date: 2026-08-20

## Context

M9 adds timers, storage, HTTP, explicit foreign ports, typed command handles,
and component-owned cancellation. ABI 5 has only transaction and region
instrumentation; effect implementations used two additional private metric
slots that the standard disposer snapshot did not disclose.

## Decision

The internal JavaScript runtime ABI becomes version 6 for every artifact. Every
mount-local metric array has ten slots. Existing transaction/DOM/trace meanings
remain at indices 0–7; index 8 counts owned commands started and index 9 counts
owned commands actually cancelled. `makeDisposer` returns defensive copies of
all ten slots, while an effect-owning disposer additionally exposes the focused
`effectInstrumentation()` pair.

Effect callbacks receive explicit state, context, opaque numeric handle, typed
result, and generated delivery function. HTTP requests carry method, URL, and
query pairs separately until the host applies `URLSearchParams`. Foreign ports
declare deterministic input/output wire metadata, sync/async mode, cancellation,
errors, trust, and security notes. Structured port types are deliberately
separate from `RuntimeTypeId` and reactive equality, and type-indexed `PortRep`
evidence prevents a caller from attaching record/array metadata to an unrelated
Lean payload. Generated update handlers commit state and render before
interpreting the returned ordered command batch.

## Consequences

ABI-5 and ABI-6 artifacts/hosts must not be mixed. All manifests and consumers
move to version 6 even when they do not execute commands. JavaScript promise,
fetch, storage, timer, decoder, cancellation, and DOM behavior remain in the
trusted computing base; native mocks, deterministic artifacts, differential
fixtures, fake-host tests, and Chromium provide executable evidence rather than
a formal backend proof.

## Validation

Runtime tests cover success, error, replacement, abort, missing foreign ports,
hostile rejected promises, reentrant/throwing/rejected cancellation callbacks,
delivery failure, and disposal without unhandled rejection. Entry-identity tests
also ensure stale completion from a reused numeric handle cannot affect its
replacement. Notes and Issue Browser cover owned commands through public APIs in
Chromium, including independent persistence failures and duplicate keyed data.
Every generated artifact is built twice and byte-compared, and every manifest
consumer requires ABI 6.
