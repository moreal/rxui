# ADR-0008: Bump the internal runtime ABI for M5 transactions

- Status: Accepted
- Date: 2026-08-19

## Context

M5 changes generated event handlers from direct state/ref arguments to a
mount-local transaction context, adds nested depth and sink caches, and adds a
public disposer instrumentation accessor. Reusing M4's runtime ABI version 1
would let incompatible hosts and artifacts appear compatible.

## Decision

The internal JavaScript runtime ABI becomes version 2. Every scalar and component
manifest records this major version. The DOM listener call shape remains stable,
but `makeDisposer` now receives private metrics and installs an accessor that
returns copied counters and a copied trace. The generated scheduler retains the
only mutable transaction-control reference; instrumentation consumers cannot
mutate scheduling state.

## Consequences

M4 ABI-1 artifacts and M5 ABI-2 artifacts must not be mixed. Any cache, host, or
tool that consumes manifests must reject a version mismatch. Generated source,
manifest goldens, native/Node differentials, component determinism, and Chromium
tests move together.

## Validation

All manifest consumers require version 2. A browser regression mutates the
returned instrumentation snapshot before nested dispatch and verifies the real
transaction still performs one commit with the expected DOM and fresh snapshot.
