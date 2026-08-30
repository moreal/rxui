# Writing components

LeanRx offers explicit checked values and an opt-in scoped component surface.
Start with the scoped surface; use the explicit API when building reusable
helpers or inspecting the exact terms.

## A complete component

```lean
import LeanRx

namespace MyApp

open LeanRx
open scoped LeanRxDsl

abbrev CounterSchema : Schema :=
  .field "count" Int <| .field "label" String .empty

def count : Field CounterSchema Int := .here
def label : Field CounterSchema String := .there .here

component Counter (schema := CounterSchema) where {
  state count : Int := 0;
  derived label := rx% s!"Count: {count}";
  event increment := set count (count + 1);
  view := jsx% <main> [
    <h1> [{"countLabel": rx% label}],
    <button type="button" onClick={increment}> ["Increment"]
  ];
}

end MyApp
```

The command generates inspectable `_schema`, `_declarations`, `_spec`, and
`_check` names. Checking validates field roles, dependency cycles, event/update
compatibility, safe view structure, and backend support before emission.

## Component rules

- Use `state` for event-writable sources and `derived` for staged values.
- Keep expressions inside `rx%`; unsupported operations are compile errors.
- Bind clicks to native buttons. The view DSL does not turn a generic element
  into a synthetic control.
- Use semantic tags and visible labels. Icon-only controls need `ariaLabel`.
- Treat the closed tag, attribute, event, and payload vocabularies as the real
  browser API.
- Prefer composition. A capitalized component head mounts another checked
  component with independent state and disposal.

## Reusable source-owned UI

`LeanRx.UI` currently provides three small primitives:

```lean
UI.button "Continue" "continue" .primary
UI.callout "Heads up" (View.node .p [.text "Typed and source-owned."])
UI.codeBlock "sampleSource" sampleExpression
```

They return ordinary `View` values, so applications can copy, inspect, and
adapt the Lean source. This is a starter kit, not a complete component library:
there are no dialog, menu, popover, focus-trap, toast, or registry tools yet.

See the full [language guide](language.md) for typed form payloads, regions,
row events, composition, effects, routes, and persistence.
