# ADR-0038: Reflect controlled inputs through the generic component backend

- Status: Accepted
- Date: 2026-08-25

## Context

ADR-0037 gave the generic component backend one-way typed payloads
(`input`/`keydown`/`change` into a source slot), but everything a controlled
form needs beyond that stayed bespoke: reflecting `value`/`checked` back into
the DOM, `Bool` checkbox payloads, and prevented `submit` lived only in the
hand-written Temperature/ValidatedForm backends (ADR-0013, ADR-0021). A
`component`-command input could read the user but never be reset, checked, or
submitted, so Echo Lab's Clear button could not clear its own input.

## Decision

Extend the generic pipeline with reflected properties and the remaining form
events, reusing only host exports that shipped with ABI ≤ 15:

- The safe view gains `PropBinding` — `value (RxExpr Γ deps String)` and
  `checked (RxExpr Γ deps Bool)` — carried on `View.element` beside static
  attributes and events. The constructor fixes both the compiler-owned DOM
  property name and the only expression type it accepts. `jsx%` spells them
  `value={rx% …}` / `checked={rx% …}`; they are valid only on `input`
  elements (`LRX-VIEW-020`) and may not repeat (`LRX-VIEW-021`).
- Reflected properties join the planned graph as sink nodes
  (`prop:{index}:{name}`) and the transaction shell as a third commit sweep:
  when a dependency changed, evaluate, compare against `propCache`, and write
  through the ABI-11 `setProperty` host, counting evaluations in `tx[8]` and
  DOM writes in `tx[9]`. `propRefs`/`propCache` ride the mount context at
  slots 6 and 7 and exist only when a component reflects at least one
  property. The cache-guarded write may re-assign the string the user just
  typed; per the WHATWG value setter, an equal-value assignment does not move
  the caret, and the browser gate pins mid-text cursor preservation.
- `EventKind` gains `checkedChange` (DOM `change`, payload class `checked`)
  and `submit` (payload-less, `form` elements only, `LRX-VIEW-019`).
  `ComponentSpec.typedEvents` widens from `TypedEventSpec Γ String` to the
  closed union `AnyTypedEvent` (`string`/`bool`); the item surface accepts
  `event name (param : Bool) := set field param;` (`LRX-ELAB-109` for other
  payload types), and validation checks each payload binding against the
  declared payload type (`LRX-VIEW-018`). Bindings mount through the existing
  `listenChecked` and `listenSubmit` hosts; `HtmlTag` gains `form`, and
  `StaticAttr` gains the closed `inputType` (`text`/`checkbox`, `input`
  elements only, `LRX-VIEW-022`).
- The `setProperty` dom-host import, the form-event host import (now also
  triggered by `submit`), and the `controlled-props` feature flag appear only
  when used. No new host exports; the runtime ABI stays 15, and components
  without reflected properties or the new event kinds emit byte-identical
  modules and manifests.

## Consequences

- `examples/EchoLab.lean` dogfoods the surface: a controlled draft input, a
  reflected checkbox with a `Bool` typed event, a controlled note input, and
  a `form onSubmit` that commits the draft. `Test/browser/echo.spec.mjs`
  gates controlled resets, mid-text cursor preservation, checkbox payloads,
  and prevented submission in Chromium; `Test/js/echo_artifacts.mjs` pins the
  manifest, listener wiring, and property writes.
- Counter, DiamondLab, and every other component-backend artifact stayed
  byte-identical through the change, keeping the ADR-0031/0032 benchmark
  freeze intact.
- Transforming reflections (`value={rx% f draft}` with `f` not the identity)
  legitimately move the caret to the end when `f` changes the text; the
  generic backend does not attempt the bespoke Temperature cache-seeding.
