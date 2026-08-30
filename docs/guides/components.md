# Writing components

LeanRx offers explicit checked values and an opt-in scoped component surface.
Start with the scoped surface; use the explicit API when building reusable
helpers or inspecting the exact terms.

## Mental model

```text
state ──event writes──▶ transaction ──changed fields──▶ derived values
                                                          │
                                                          ▼
                                      text/property/attribute sinks ──▶ DOM
```

The arrows are known before emission. `rx%` records typed dependencies, the
component checker builds and schedules the graph, and generated code updates
only the affected frontier. `jsx%` is a checked view description, not a Virtual
DOM tree that is diffed after every event.

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

Read the declaration from top to bottom:

1. `schema` fixes the ordered runtime slots and their Lean types;
2. `state` introduces writable sources;
3. `derived` introduces cached staged computations;
4. `event` describes a closed source update or supported command sequence;
5. `view` binds static structure and reactive sinks;
6. the generated `_check` is either a private checked component or a
   source-linked error.

Names and roles are not documentation-only metadata. They appear in graph and
manifest artifacts and are checked against the declaration inventory.

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

## State, derived values, and events

Put mutable facts in `state`; put reproducible presentation or calculation in
`derived`. An event reads the source snapshot, applies its writes in declaration
order, and commits once. Derived caches then run in topological order. Equality
can stop propagation, and a sink writes the DOM only when its rendered output
actually changes.

This has two practical consequences:

- do not duplicate derived data into writable state merely to render it;
- do not expect an event to read a just-recomputed derived field. That boundary
  is rejected as `LRX-TYPE-108`; compute from sources or keep the calculation in
  a derived node.

Use typed payload events for browser values rather than reaching for an event
object. For example, a text input delivers a `String` to an `onInput` event and
a checkbox delivers a `Bool` to `onCheckedChange`. The host owns extraction and
the component owns the state update.

## Static and dynamic shape

Ordinary `jsx%` nodes form one static owned tree. Dynamic text and selected
properties update retained nodes directly. When DOM shape must change, use a
named checked capability:

| Need | Capability |
|---|---|
| choose one local subtree | conditional/branch region |
| preserve rows by identity | keyed `region` |
| update one row from its controls | sealed `row` event |
| nest independently stateful UI | capitalized checked component reference |
| own timers, storage, HTTP, or a foreign call | typed command/effect contract |

Those capabilities have narrower expression and event vocabularies than general
Lean. Consult the [language guide](language.md) and
[backend matrix](backend-support.md) before designing around an assumed escape
hatch.

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

## Authoring checklist

Before calling a component ready:

1. type-check the defining Lean module;
2. inspect `_check` or run `leanrx check` for a registered component;
3. inspect the graph after adding or changing dependencies;
4. verify native semantics and generated browser behavior at every new boundary;
5. exercise keyboard, accessible names/states, hostile text, and disposal;
6. inspect the adjacent manifest when runtime features or host imports change.

See the full [language guide](language.md) for typed form payloads, regions,
row events, composition, effects, routes, and persistence.
