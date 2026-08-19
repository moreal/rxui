# ADR-0006: Use scoped balanced component and JSX syntax

- Status: Accepted
- Date: 2026-08-19

## Context

M4 requires public `component`, declaration-role, and minimal JSX-like syntax.
Registering `state`, `derived`, `event`, and `view` as unscoped Lean keywords
would prevent ordinary declarations and local variables from using those names.
Parsing paired arbitrary HTML closing tags would also require a substantially
larger custom parser before the static DOM semantics are stable.

## Decision

The M4 surface is enabled explicitly with `open scoped LeanRxDsl`. A component
uses braced, semicolon-terminated declaration items whose right-hand sides are
ordinary checked `ValueSpec`, `EventSpec`, and `View` terms. The JSX-like view
uses HTML-shaped opening tags and a balanced Lean child list:

```lean
open scoped LeanRxDsl

def counterView := jsx% <main class="counter"> [
  <button type="button" onClick="increment"> ["Increment"],
  <p> [{"countText": countText}]
]

component Counter (schema := CounterSchema) where {
  state count := ValueSpec.state count (.int 1);
  derived doubled := ValueSpec.computed doubledField doubled;
  event increment := increment;
  view := counterView;
}
```

The string preceding an interpolation is its stable sink name. Tags, static
attributes, and event attributes remain closed whitelists. Raw HTML and unknown
attributes fail during macro expansion with stable `LRX-DOM-*` diagnostics.

## Alternatives considered

- Global keywords make the target syntax slightly shorter but pollute every
  module importing `LeanRx`.
- Paired closing tags are more familiar, but matching arbitrary tag tokens needs
  parser machinery unrelated to the M4 semantic thesis.
- A string-template parser would weaken source locations and typed interpolation.

## Consequences

The M4 syntax differs slightly from the illustrative target in `PLAN.md`, for a
recorded Lean parser/scoping reason. It still elaborates to inspectable generated
`*_schema`, `*_declarations`, `*_spec`, and `*_check` declarations. A later
surface parser can target the same public core without changing graph, proof,
backend, or host layers.

## Validation

Counter is generated through this syntax and passes native validation,
determinism, Node import, Chromium updates/disposal, hostile-text, keyboard, and
axe gates. Compile-fail fixtures cover unsupported tags, unknown attributes, raw
HTML, and missing component views.
