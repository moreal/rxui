# ADR-0037: Lower typed event payloads through the generic component backend

- Status: Accepted
- Date: 2026-08-24

## Context

Typed browser payloads existed only in the bespoke form backends: the M6
`TypedEventSpec` and the `listenValue`/`listenChecked`/`listenKey` host
adapters (ADR-0013, ADR-0021) served TemperatureConverter and ValidatedForm,
while the generic component backend knew only payload-less `click`/`dblclick`
dispatch. A component built from the `component` command could not react to
text input at all.

## Decision

Extend the generic pipeline end to end while keeping the payload-less path
byte-stable:

- `EventKind` gains `input`, `keydown`, and `change`, classified by a new
  `EventPayload` (`none`/`value`/`key`). The `jsx%` attributes `onInput`,
  `onKeyDown`, and `onChange` produce these bindings on `input` elements only
  (`LRX-VIEW-016`).
- `ComponentSpec` gains `typedEvents : Array (TypedEventSpec Γ String)`,
  declared with `event name (param : String) := set field param;`
  (ADR-0036). Validation extends the existing gates: shared name uniqueness
  (`LRX-ELAB-102`), source-only targets (`LRX-TYPE-107`), payload bindings
  must name a declared typed event (`LRX-VIEW-017`), and typed events join
  the surface alignment and event summaries.
- `Backend.Component` emits one dispatch function per typed event
  (`$lrx_typed_event_i(hostState, context, value)`) sharing the exact
  transaction shell of the payload-less events — begin bookkeeping, the
  single payload write, and the derived/sink commit sweep — and mounts the
  binding through `listenValue`/`listenKey` from `leanrx_form_events.mjs`.
  The host import, the manifest `hostImports` entry, and the `typed-events`
  feature flag appear only when payload bindings exist, and `eventCount`
  counts both event tables. A payload parameter that would shadow a shell
  local is rejected (`LRX-BE-028`).
- No new host exports: the adapters shipped with runtime ABI 11 and the ABI
  stays at 15. `checkedChange`/`focus`/`submit` and reflected DOM properties
  (controlled inputs) remain with the bespoke form backends; the generic
  surface is one-way payload-to-source assignment.

## Consequences

- `examples/EchoLab.lean` dogfoods the surface — `onInput`, `onKeyDown`, and
  `onChange` beside a payload-less clear button — and
  `Test/browser/echo.spec.mjs` gates per-keystroke updates, blur-commit
  semantics, mixed listeners, and disposal in Chromium;
  `Test/js/echo_artifacts.mjs` pins the manifest and the generated listener
  wiring, and `scripts/check_component_codegen.sh` pins determinism.
- Components without typed events emit byte-identical modules and manifests;
  Counter and DiamondLab prove it.
- The logical reference view still rejects every event binding
  (`LRX-VIEW-013`); its event-free design is intentional.
