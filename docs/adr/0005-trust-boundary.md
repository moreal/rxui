# ADR-0005: Limit proof claims and document the remaining TCB

- Status: Accepted
- Date: 2026-08-19

## Context

A Lean proof about an abstract finite DAG does not prove a custom JavaScript
emitter, JavaScript engine, or browser DOM correct.

## Decision

Pure semantics and named theorems are kernel checked without placeholders or
hidden axioms. The emitter, runtime representation, browser host, JavaScript
engine, DOM, selected Lean library semantics, kernel, and toolchain remain in the
documented trusted computing base unless a later proof removes them.

## Alternatives considered

- Calling browser behavior “verified” based only on source semantics would
  overstate the evidence.
- Tests alone cannot replace the central abstract propagation proof.

## Consequences

Proof, executable validation, differential evidence, and trusted assumptions are
reported separately. Unsafe or partial semantic definitions are forbidden;
metaprogramming uses of unsafe APIs are isolated and excluded from proof claims.

## Validation

Placeholder scans, axiom manifests, `lean4checker` where applicable, differential
tests, browser tests, and final claim review enforce the boundary.

## Reviewed M0 axiom manifest

Lean 4.33 generates constructor-injectivity theorems for universe-bearing
schemas/fields and source-position structures that depend on the kernel's
standard `propext` axiom. These generated theorems are not LeanRx semantic
claims. `Test/Policy/EnvironmentAudit.lean` lists every exact theorem/axiom pair
and rejects every unlisted or changed pair.

Lean also generates `_unsafe_rec` compiler helpers for safe source definitions
that eliminate universe-bearing schemas/fields. The source declarations remain
kernel checked and semantic modules contain no written `unsafe` declaration.
The environment audit exact-lists these generated helpers; any new unsafe or
partial declaration fails until separately reviewed.
