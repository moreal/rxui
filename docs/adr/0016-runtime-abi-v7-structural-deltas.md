# ADR-0016: Bump the internal runtime ABI for structural deltas

- Status: Accepted
- Date: 2026-08-21

## Context

M10 compares full keyed reconciliation with an explicit structural-delta path
and a cost-model hybrid on the same checked 10,000-row component. ABI 6 exposes
only full target-list reconciliation. Treating the new delta entry point as an
unversioned helper would allow an artifact to advertise compatibility with a
host that cannot provide its required structural contract.

## Decision

The internal JavaScript runtime ABI becomes version 7 for every artifact. The
region host adds `createDeltaKeyedRegion`, which consumes a closed tagged delta
vocabulary produced by the checked backend. It validates an entire batch,
including bounds, key identity, uniqueness, and move targets, before mutating
owned DOM. Its copied focused instrumentation reports mounts, retained updates,
moves, disposals, full resets, accepted delta operations, and validation visits.

The existing ten-slot transaction/effect instrumentation, scalar value
representations, equality plans, DOM host, and effect host are unchanged. The
delta adapter remains local and mechanical: generated application code chooses
the strategy and supplies operations; the host neither discovers dependencies
nor schedules reactivity.

## Consequences

ABI-6 and ABI-7 artifacts/hosts must not be mixed. All deterministic manifests
and consumers move to version 7, including applications that do not import the
delta region entry point. The delta runtime, generated strategy selection,
typed JavaScript emitter, DOM, and browser remain in the trusted computing base.
Pure `ListDelta` correctness establishes the checked target list in Lean; it
does not formally verify the JavaScript host connection.

## Validation

Fake-DOM tests cover every delta constructor, retained identity, disposal,
copied instrumentation, full-batch fail-before-mutation, duplicate keys, and
idempotent disposal. Deterministic generation and Node syntax checks cover all
artifacts at ABI 7. The Data Grid browser gate executes full, delta, and hybrid
strategies against the same native oracle, checks their final logical equality,
and records structural work separately from wall-clock measurements.
