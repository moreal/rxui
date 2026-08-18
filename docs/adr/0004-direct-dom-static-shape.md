# ADR-0004: Use direct DOM updates for static shape

- Status: Accepted
- Date: 2026-08-19

## Context

For static UI shape the compiler already knows each scalar sink's target DOM node.
A global Virtual DOM would obscure this relationship and add reconciliation work.

## Decision

Mount static element structure once and compile reactive text, attributes,
properties, and handlers to explicit sinks. A tiny host owns real DOM operations
but contains no dependency discovery or scheduling. Later dynamic regions may use
local reconciliation without introducing a root VDOM.

## Alternatives considered

- A global VDOM is established prior art but does not test the direct-sink thesis.
- Handwritten DOM updates in examples would bypass the public compiler contract.

## Consequences

Disposal and ownership are explicit. Scalar updates target known nodes directly.
Conditional and list shape wait until the scalar semantics and browser gates pass.

## Validation

Browser tests cover mount, exact updates, work suppression, isolation, hostile
text, and idempotent disposal. Source scans reject banned discovery mechanisms.
