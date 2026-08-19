# ADR-0010: Bump the internal runtime ABI for dependent values

- Status: Accepted
- Date: 2026-08-19

## Context

M6 adds `Vector α n` arrays, erased `Fin n` indices, immutable vector props, and
typed event payloads. Although the tiny host call shapes remain compatible,
artifacts and tools that only understand the scalar runtime codes cannot safely
consume the new manifests or event/value conventions under ABI version 2.

## Decision

The internal JavaScript runtime ABI becomes version 3 for every generated
artifact. `Vector α n` values contain only the ordered element array; `n` and
constructor evidence are absent. `Fin n` values contain only an array-compatible
JavaScript number; the backend accepts statically generated indices only when
the vector length is below `UInt32.size`. Typed event functions receive that
erased index and assign it only to a definitionally matching state field.

## Consequences

ABI-2 and ABI-3 artifacts must not be mixed. Every manifest consumer moves to
version 3 even when a particular scalar artifact does not use dependent values.
Foreign code remains responsible for validating values before crossing a port;
the public dependent component path does not expose an unchecked event function.

## Validation

Native tests check the indexed representations and typed assignment contract.
Reactive IR analysis records erased length/bound evidence and rejects evidence
inspection. Native-to-Node cases execute safe vector reads, generated Tabs
artifacts are determinism-checked, and browser tests exercise every generated
finite event handler without serializing proof objects.
