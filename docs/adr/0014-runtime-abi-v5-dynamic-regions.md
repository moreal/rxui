# ADR-0014: Bump the internal runtime ABI for dynamic regions

- Status: Accepted
- Date: 2026-08-19

## Context

M8 adds local conditional, positional, and keyed shape reconciliation plus
delegated events for rows whose DOM identity survives reorder. ABI 4 has form
payload adapters but no fixed delegated-row payload contract or region module.

## Decision

The internal JavaScript runtime ABI becomes version 5 for every artifact. The DOM
host adds `listenDelegated`, which searches only the compiler-owned
`data-lrx-action` marker inside the registered region root and passes fixed
action/key/value/checked/key-name fields to a generated handler. The separate
`leanrx_region.mjs` module receives explicit target arrays and generated
mount/update/dispose callbacks. It owns local DOM ordering and ownership only; it
does not discover dependencies, run transactions, or implement application
updates.

## Consequences

ABI-4 and ABI-5 artifacts/hosts must not be mixed. Existing manifest consumers
move to version 5 even when they do not use regions. Region callbacks and the
generated application reducer remain in the backend/browser TCB; the pure region
theorems do not verify this host connection.

## Validation

All existing generated modules remain deterministic and browser-green at ABI 5.
Fake-DOM tests cover the region module. TodoMVC browser tests must cover delegated
event routing after reorder, retained identity/focus, removal disposal, hostile
text, and no full-root rebuild.
