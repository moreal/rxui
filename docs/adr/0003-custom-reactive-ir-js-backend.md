# ADR-0003: Use a custom Reactive IR to JavaScript backend

- Status: Accepted
- Date: 2026-08-19

## Context

Transpiling arbitrary Lean compiler IR requires broad, version-sensitive runtime
compatibility unrelated to the initial static-reactivity research question.

## Decision

The primary browser path lowers kernel-checked staged terms to a project-owned,
first-order Reactive IR, then to a validity-checked JavaScript AST and
deterministic ESM printer.

## Alternatives considered

- Reusing Qed's general Lean IR backend would couple LeanRx to a larger ABI and a
  different VDOM/Elm architecture.
- Direct string concatenation would make invalid syntax and escaping bugs easy.

## Consequences

The supported subset is explicit and initially narrow. Every unsupported
construct is a build error. A future Lean IR bridge, if justified, is isolated and
requires a separate ADR and upgrade surface.

## Validation

AST negative tests, golden output, native-vs-JavaScript differential tests, and
repeated-build byte comparisons gate M3 onward.
