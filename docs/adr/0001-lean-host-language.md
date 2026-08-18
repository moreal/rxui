# ADR-0001: Lean 4 is the host language

- Status: Accepted
- Date: 2026-08-19

## Context

LeanRx needs dependent types, total functions, custom syntax, elaboration, and
kernel-checked proofs without inventing a new type theory.

## Decision

Application and framework source use the exact stable Lean toolchain pinned in
`lean-toolchain`. Lean syntax and elaborator extensions provide the UI language.

## Alternatives considered

- A standalone parser and type checker would enlarge the trusted core and repeat
  capabilities Lean already supplies.
- TypeScript would ease browser interop but would not provide the proof model the
  research thesis requires.

## Consequences

Lean release changes are explicit upgrades. Release-sensitive APIs are isolated
and documented. Generated declarations remain inspectable by ordinary Lean tools.

## Validation

`lake build`, native tests, proof checks, and the upgrade checklist gate changes.
