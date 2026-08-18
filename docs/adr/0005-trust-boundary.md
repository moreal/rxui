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
