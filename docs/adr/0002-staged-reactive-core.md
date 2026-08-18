# ADR-0002: Use a typed staged reactive core

- Status: Accepted
- Date: 2026-08-19

## Context

Precise compile-time dependencies and write capabilities cannot be recovered
soundly from unrestricted functions over a whole mutable component state.

## Decision

Reactive expressions, updates, and views elaborate to explicit typed terms.
Dependency and effect sets are encoded in, or checkably derived from, those terms.
Ordinary Lean helpers may operate on already-read values within the supported
lowerable subset.

## Alternatives considered

- Runtime subscriber discovery violates the static-graph thesis.
- Elaborator-only dependency tables could omit reads without kernel detection.
- Whole-state functions destroy precise dependency information.

## Consequences

The staged subset is intentionally smaller than Lean. Unsupported constructs fail
with source-linked diagnostics. Pure terms remain independently callable and
testable without CLI or filesystem IO.

## Validation

M1 proves evaluation congruence on declared dependencies; compile-fail fixtures
later reject state escape and illegal effects.
