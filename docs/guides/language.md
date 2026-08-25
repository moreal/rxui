# LeanRx language guide

LeanRx is a restricted staged language embedded in Lean 4. Lean checks the host
program, schema indices, dependent values, and proofs; LeanRx compiles only its
own closed expression, component, view, command, and region vocabularies. It is
not an arbitrary Lean-to-JavaScript transpiler.

The repository is not a released package and has no selected license. Examples
below assume this checkout and the exact toolchain in `lean-toolchain`.

## 1. Define a typed store schema

A `Schema` is an ordered heterogeneous list. A `Field Γ α` is a typed capability
to one slot; field construction cannot name a slot with the wrong Lean type.

```lean
import LeanRx

open LeanRx

abbrev CounterSchema : Schema :=
  .field "count" Int <| .field "label" String .empty

def count : Field CounterSchema Int := .here
def label : Field CounterSchema String := .there .here
```

Field order is the stable source/derived slot order used by dependency sets,
graphs, manifests, and generated storage. Runtime browser values are restricted
to representations supported by `RuntimeType`: currently Bool, String, Int, Nat,
fixed `Vector`, and bounded `Fin` in their checked contexts. An unsupported read
fails at construction or lowering rather than acquiring an invented encoding.

## 2. Build staged expressions

`RxExpr Γ deps α` carries its complete direct dependency set in the type. Reads,
literals, scalar primitives, conditionals, and checked vector access compute the
set compositionally.

```lean
def doubled := RxExpr.binary .intMul
  (RxExpr.read count)
  (RxExpr.literal (.int 2))

def countText := RxExpr.binary .stringAppend
  (RxExpr.literal (.string "Count: "))
  (RxExpr.unary .intToString (RxExpr.read count))
```

Condition dependencies conservatively include the condition and both branches.
Lean native evaluation remains available through `RxExpr.eval`, which is useful
for native oracles and differential tests. Browser lowering supports only the
closed matrix in the [backend support guide](backend-support.md).

## 3. Declare sources and derived values

`ValueSpec.state` introduces a source with an initial scalar value.
`ValueSpec.computed` binds a staged expression to a later schema field. Sources
must form a leading prefix, names must match their declared surface roles, and
the checked graph validates dependencies, equality plans, ranks, and schedule.

```lean
def values : Array (ValueSpec CounterSchema) := #[
  ValueSpec.state count (.int 1),
  ValueSpec.computed label countText
]
```

The compiler derives representation and lawful equality metadata. Callers do not
attach an arbitrary equality strategy to a typed value.

## 4. Define events

An `EventSpec Γ` contains a closed, pure update description. The basic scalar
form sets a source from a staged expression:

```lean
def increment : EventSpec CounterSchema :=
  { name := "increment"
    update := .set count <| RxExpr.binary .intAdd
      (RxExpr.read count) (RxExpr.literal (.int 1)) }
```

Transactions apply source writes in order, compare the final source snapshot,
then propagate one affected derived phase in topological order and one sink
phase. Nested dispatch shares the outer transaction. A source written and then
restored schedules no downstream work. Event expressions currently read sources,
not freshly recomputed derived values; `LRX-TYPE-108` reports that boundary.

Specialized public specifications extend this vocabulary for dependent Tabs,
controlled forms, dynamic regions, owned effects, and the fixed structural-delta
experiment. Each remains closed and checked; application JavaScript is not the
extension mechanism.

## 5. Build a safe view

The scalar view is a small static tree. Dynamic interpolation creates or updates
text nodes. Raw HTML has no constructor.

```lean
def counterView : View CounterSchema := View.node .main [
  View.node .h1 [.text "Counter"],
  View.node .button [.text "Increment"]
    (attrs := [.buttonType .button])
    (events := [{ kind := .click, eventName := "increment" }]),
  View.node .p [.scalarText "countText" countText]
]
```

Click bindings are accepted only on native buttons. Static tag, attribute, and
event names come from closed enums; hostile strings reach text/attribute values,
not HTML or JavaScript source. The available elements and attributes are
deliberately limited; see [accessibility](accessibility.md) before inventing a
control from a generic element.

## 6. Check an explicit component

```lean
def spec : ComponentSpec CounterSchema :=
  { name := "Counter"
    values
    events := #[increment]
    view := counterView }

def checked := spec.check
```

`ComponentSpec.check` is pure and returns either a source-linked
`ComponentError` or a private `CheckedComponent`. The private constructor is the
boundary consumed by graph serialization and the component backend.

## 7. Use the scoped component surface

The optional surface records role/name/span declarations and generates
inspectable names. It is activated explicitly:

```lean
open scoped LeanRxDsl

component CounterSyntax (schema := CounterSchema) where {
  state count : Int := 1;
  derived label := rx% s!"Count: {count}";
  event increment := set count (count + 1);
  view := jsx% <main> [
    <h1> ["Counter"],
    <button type="button" onClick={increment}> ["Increment"],
    <p> [{"countText": rx% s!"Count: {count}"}]
  ];
}
```

`state name : Type := literal` covers the closed literal types `Int`, `Nat`,
`Bool`, and `String`; the declared identifier is also the schema `Field`
reference. A `derived` right-hand side may be a staged `rx%` expression or an
explicit `ValueSpec`. Events chain steps with `then`
(`set count (count + 1) then dispatch increment`), and a typed payload event
is declared `event setDraft (value : String) := set draft value;` and bound
with `onInput={setDraft}`, `onKeyDown={…}`, or `onChange={…}` on an `input`
element. `onClick={increment}` binds by reference against the declared event
inventory (or an `EventSpec` in scope outside a component). The explicit
wrapper forms remain valid:

Controlled inputs reflect state back into the DOM (ADR-0038): `value={rx% …}`
and `checked={rx% …}` are property reflections valid only on `input` elements,
`type="text"`/`type="checkbox"` select the input control, a `Bool` payload
event (`event toggleLoud (checked : Bool) := set loud checked;`) binds with
`onCheckedChange={toggleLoud}`, and a `form` element takes a payload-less
`onSubmit={save}` whose host adapter owns `preventDefault`:

```lean
component EchoMini (schema := EchoMiniSchema) where {
  state draft : String := "";
  state loud : Bool := false;
  event save := set draft "";
  event setDraft (value : String) := set draft value;
  event toggleLoud (checked : Bool) := set loud checked;
  view := jsx% <main> [
    <form onSubmit={save}> [
      <input ariaLabel="Draft" value={rx% draft} onInput={setDraft} />,
      <input ariaLabel="Loud" type="checkbox" checked={rx% loud} onCheckedChange={toggleLoud} />,
      <button type="submit"> ["Save"]
    ]
  ];
}
```

An attr-less capitalized element statically nests another checked component
when its `_spec` is in scope (ADR-0039): `<EchoMini/>` inside a later
component's view records `EchoMini` in the parent's child table, and the
parent's generated module imports and mounts `./EchoMini.mjs` in document
order with fully independent state and disposal. A capitalized head without a
matching `_spec` keeps its ordinary meaning as a typed view-term application.

A `region` item declares a keyed list with a sealed row template (ADR-0040,
ADR-0041): rows are `String` tuples behind region-owned monotone keys,
`{field}` children project row fields, and `onClick={remove}` binds the sealed
`remove` row action, which lowers to one structural delegated listener on the
region's container. `<region name/>` mounts the region as the only child of
its container element, and the `append name (expr, …)` event step pushes a row
whose field values are staged over component state:

```lean
component RosterMini (schema := RosterMiniSchema) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}") then set added (added + 1);
  region roster (label) := jsx% <li> [
    <span> [{label}],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
```

The delegated button must sit strictly inside a row cell (a direct child of
the row root) so the dispatcher can resolve the action from row structure —
`LRX-VIEW-027` rejects a button that is itself a cell.

A `row` item declares a sealed update action on a region's rows (ADR-0043):
`row roster mark := set marks (marks ++ " ★");` writes new field values —
evaluated simultaneously against the dispatching row's current fields — and
re-renders exactly that row through the region handle's `updateAt`. Row
expressions are sealed: bare row fields, string literals, and `++`
(`LRX-ELAB-115` otherwise); they also serve dynamic row text, so `{label ++
marks}` renders a concatenation that tracks row updates. A row element may
select its class from row state (ADR-0044) with
`class={if marks == "" then "roster-row" else "roster-row marked"}` — the
predicate is equality of one row field against one string literal and both
classes are static strings (`LRX-ELAB-116` otherwise):

```lean
component MarkedRosterMini (schema := MarkedRosterMiniSchema) where {
  state markedAdded : Int := 0;
  event addItem := append roster (s!"Item {markedAdded}", "")
    then set markedAdded (markedAdded + 1);
  row roster mark := set marks (marks ++ " ★");
  region roster (label, marks) := jsx%
    <li class={if marks == "" then "row" else "row marked"}> [
      <span> [{label ++ marks}],
      <span> [<button type="button" ariaLabel="Mark" onClick={mark}> ["★"]],
      <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
    ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
```

A `row` item may declare one `String` payload parameter (ADR-0046):
`row roster rename (value : String) := set label value;` receives the
delegated payload in its right-hand sides through the parameter name. The
template binds payload-taking events on native `input` elements —
`onInput={rename}` delivers the input's value and `onKeyDown={record}`
delivers the pressed key — and each payload-taking event must be bound
exactly once so its payload class is determined by that binding
(`LRX-VIEW-033` otherwise). Payloads are `String` only, the parameter cannot
shadow a row field (`LRX-ELAB-117`), and `key` itself stays a reserved
surface keyword, so name the keydown parameter something else:

```lean
component EditableRosterMini (schema := EditableRosterMiniSchema) where {
  state editAdded : Int := 0;
  event addItem := append roster (s!"Item {editAdded}", "")
    then set editAdded (editAdded + 1);
  row roster rename (value : String) := set label value;
  row roster record (pressed : String) := set lastKey ("key:" ++ pressed);
  region roster (label, lastKey) := jsx% <li> [
    <span> [{label}],
    <span> [{lastKey}],
    <span> [<input ariaLabel="Rename" onInput={rename} onKeyDown={record} />],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
```

Rows never observe component state after mount: row expressions read only
row fields plus the declaring event's payload, `remove` and declared
`update` events are the whole action vocabulary, and each cell binds at most
one row event per delegated kind (`click`, `input`, `keydown`).

A static view element may select its `class`, `aria-pressed`, or `disabled`
from component state (ADR-0045):
`class={if filter == "all" then "selected" else ""}` selects between two
static class strings, `ariaPressed={filter == "all"}` reflects the equality
as `"true"`/`"false"`, and `disabled={filter == "all"}` reflects it as the
boolean element property. The predicate is equality of one `String`
component value (source or derived) against one string literal; the field
reference is the ordinary schema `Field`, so a non-`String` field is a plain
Lean type error. Selections join the commit sweep beside text sinks and
reflected properties with the evaluate-compare-write shape. A selection
counts as its attribute for duplicate detection (`LRX-VIEW-001`), and
`aria-pressed`/`disabled` selections require a native button
(`LRX-VIEW-032`); other shapes report the sealed surface (`LRX-VIEW-012`):

```lean
component FilterMini (schema := FilterMiniSchema) where {
  state filter : String := "all";
  event showAll := set filter "all";
  event showActive := set filter "active";
  view := jsx% <main> [
    <button type="button" onClick={showAll}
        class={if filter == "all" then "selected" else ""}
        ariaPressed={filter == "all"}> ["All"],
    <button type="button" onClick={showActive}
        class={if filter == "active" then "selected" else ""}
        ariaPressed={filter == "active"}> ["Active"],
    <button type="button" onClick={showAll} disabled={filter == "all"}> ["Reset"]
  ];
}
```

A `prop` item declares an immutable `String` input that the parent supplies
through the mount ABI (ADR-0042): the child renders it with a `{title}` text
child, its module's signature becomes `mount(target, props)`, and a parent
passes values as literal attributes — `<TitledMini title="Hello"/>` — which
must match the child's declared prop names and order exactly
(`LRX-ELAB-112` otherwise):

```lean
component TitledMini (schema := TitledMiniSchema) where {
  state clicks : Int := 0;
  prop title : String;
  event bump := set clicks (clicks + 1);
  view := jsx% <main> [
    <h1> [{title}],
    <button type="button" onClick={bump}> ["Bump"]
  ];
}
```

```lean
component CounterExplicitSyntax (schema := CounterSchema) where {
  state count := ValueSpec.state count (.int 1);
  derived label := ValueSpec.computed label countText;
  event increment := increment;
  view := counterView;
}
```

The complete form of this canonical snippet is compiled in
`Test/Docs/LanguageGuide.lean`. This generates `CounterSyntax_schema`, `CounterSyntax_declarations`,
`CounterSyntax_spec`, and `CounterSyntax_check`. The generated declaration
inventory is checked against the actual roles and names; it is not decorative.
Builds may emit a small `.generated.lean` alias module for editor inspection.

### Stage expressions with rx%

`rx%` stages ordinary Lean expression syntax into the same closed `RxExpr`
core the explicit constructors build — identical primitives, literals, and
dependency sets:

```lean
open scoped LeanRxDsl

def doubled := rx% count * 2
def parity := rx% if count % 2 == 0 then "even" else "odd"
def countText := rx% s!"Count: {count}"
def increment : EventSpec CounterSchema :=
  { name := "increment", update := .set count (rx% count + 1) }
```

Leaves stage by type: schema fields read, staged expressions splice, and
`Bool`/`Int`/`Nat`/`String` values lift into literals. Anything else fails
with `error[LRX-RX-001]` at the leaf.

### Target the logical region model

`jsx%` selects its lowering from the expected type. Against
`Region.LogicalNode` it produces the logical reference model used by dynamic
region applications and differential tests: attributes and text may be dynamic
terms, keyed list children lower onto the keyed region IR, and a capitalized
element nests another component as a typed application:

```lean
def TodoRow (todo : Item) (editing : Bool) (draft : String) : LogicalNode :=
  jsx% <li dataKey={toString todo.id}
      class={if todo.completed then "completed" else "active"}> [
    { if editing then draft else todo.title }
  ]

def rows (model : State) : List KeyedItem :=
  jsx% for todo in visible model key todo.id =>
    <TodoRow todo={todo} editing={model.editing == some todo.id}
      draft={model.draft}/>
```

A prop declared as an M6 `ImmutableProp` wraps its value through
`ImmutableProp.of` with the attribute name. Mode mismatches keep stable
diagnostics (`LRX-VIEW-011` keyed list in a typed view, `LRX-VIEW-012` dynamic
values in a typed view, `LRX-VIEW-013` events in the logical model). Surface
keywords (`state`, `derived`, `event`, `view`, `key`) cannot double as
identifiers where `LeanRxDsl` is open.

## 8. Compile and inspect

Registered applications can be checked and built through the repository CLI:

```sh
lake exe leanrx -- check Examples.Counter
lake exe leanrx -- graph Examples.Counter --format html > Counter.graph.html
lake exe leanrx -- build Examples.Counter --out .tmp/counter
```

Build publication is atomic and versioned. An unmanaged existing output path is
rejected. Generated artifacts include a validated ESM module, exact manifest,
JSON/DOT/HTML graphs, host modules, and application-specific editor aliases.

## 9. Dependent values, forms, regions, and effects

- `TabsSpec` accepts equal nonempty `Vector` props, `Fin` selection, and finite
  handlers. Proofs are erased and checked not to influence runtime inspection.
- Form specifications preserve raw controlled input, parse through a closed
  grammar, and expose refined submit capabilities only after validation.
- Conditional, positional, and keyed regions reconcile local dynamic shape while
  retaining stable instances and explicit disposal. There is no root Virtual DOM.
- `Cmd Msg`, resources, and foreign ports make timers, storage, HTTP, decoding,
  cancellation, stale-result suppression, and disposal ownership explicit.
- `ListDelta` is an opt-in checked library experiment, not a default core feature.

Follow the linked guides in [the documentation index](../README.md) and inspect
the corresponding public dogfood examples before using these specialized APIs.

## 10. Current limitations

LeanRx does not currently provide a URL router, general VDOM, arbitrary Lean
transpilation, raw HTML, URL attributes, a CSS DSL, SSR, hydration, a released
package, or a formal proof relating generated JavaScript to browser DOM behavior.
The self-hosted documentation site records how these gaps affect a real build.
