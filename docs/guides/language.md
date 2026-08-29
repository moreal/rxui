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
`LRX-VIEW-027` rejects a button that is itself a cell. A row template may
also compose child components (ADR-0075, ADR-0089): a capitalized
`<Chip tag={field}/>` head whose checked spec is in scope mounts one child
instance per row — mounted by the generated row mount callback, disposed on
every removal path through the row dispose callback, and republished on the
disposer's live `children` inventory. Its props are row-mount constants: a
string literal or the bare projection of one declared row field that no row
event or broadcast rewrites (`LRX-VIEW-045` otherwise, the ADR-0068 OQ1
immutable-prop boundary in row scope); and no template in the child's
*mounted tree* may carry a static `id`, because row instances are unbounded
(`LRX-ELAB-135`). That check is transitive (ADR-0090): the row lowering reads
a trail the child recorded when it elaborated, folding the child's own view,
the row templates of any region it declares, and every component it composes,
at any depth — so an id-free wrapper around an id-carrying leaf is rejected
too, and the diagnostic names the path (`Frame → Badge`). The same rule
covers the component's *own* row template (ADR-0091): a region mounts one
instance of its template per row, so a static `id` there is rejected by
`LRX-VIEW-046` — use a class. The line is the multiplication, not the module
boundary: a static `id` is rejected wherever the compiler instantiates the
carrying template more than once, and left to you (and the axe
`duplicate-id` gate) wherever it mounts once. View scope is therefore
unaffected: `<ul id="roster">` around a region is fine, and a component
composed in a view mounts once, so it may carry ids freely — only row
references consult the trail.
A template may compose **any number** of children, different components or
the same one repeated: each mounts where it sits in the template, the row
root stashes the mount returns as a list in that order, and the dispose
callback loops over the list, splicing each entry out by its own identity —
a mount return is a fresh closure per instance, so a repeated pair never
collide (ADR-0089). Everything outside that surface — a spec-less head,
children on the head, a composed prop value, or a child inside a two-branch
cell — stays rejected (`LRX-ELAB-131`/`LRX-VIEW-045`, ADR-0072/0075). The
inventory is one mount-scope array shared by every child-composing region
in the component: entries follow the static child seed in actual mount
order across regions — one contiguous run per row, in template order — and
each region's dispose callback splices only its own row's entries
(ADR-0077). A region broadcast re-renders retained rows without remounting
their children, so child state survives it.

A `row` item declares a sealed update action on a region's rows (ADR-0043):
`row roster mark := set marks (marks ++ " ★");` writes new field values —
evaluated simultaneously against the dispatching row's current fields — and
re-renders exactly that row through the region handle's `updateAt`. Row
expressions are sealed: bare row fields, string literals, `++`, and the
`trim` unary (ADR-0054) — `trim field` or `trim (expr)` strips ASCII
whitespace from both ends, aligned with Lean's `String.trim`
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
one row event per delegated kind (`click`, `dblclick`, `input`, `keydown`,
and checkbox `change` — ADR-0049).

A row cell may be a sealed two-branch selection (ADR-0047):
`{if mode == "view" then <span…/> else <input…/>}` mounts one of two
statically sealed template subtrees by equality of one row field against one
string literal. The cell mounts as one wrapper element, so it occupies
exactly one row-root child index; the retained-row update callback
re-evaluates the predicate against the wrapper's compiler-owned `$lrxBranch`
marker, updates the stable branch in place, and replaces the subtree with
one `detach` plus one `append` only on a branch change — the absent branch
does not exist in the DOM or the accessibility tree. Branch cells sit only
directly under the row root and never nest (`LRX-VIEW-034`). Because the
delegated action arrays are static, both branches must bind the same action
for a kind; a one-branch binding is allowed only when the other branch
cannot originate that kind — never for `click` or `dblclick` (any content
bubbles one), only input-free branches for `input` and checkbox `change`,
and only input- and button-free branches for `keydown` (`LRX-VIEW-034`). A row `input` may also reflect a
sealed row expression into its `value` property with `value={draft}` — at
most once per element, inputs only (`LRX-VIEW-035`); a row update driven by
the input's own payload writes back the string the input already holds, so
the WHATWG equal-value assignment preserves the caret (ADR-0038, reused in
row scope). A branch-subtree input may additionally carry the bare
`autoFocus` marker (ADR-0048): inputs only, branch subtrees only, at most
one per subtree (`LRX-VIEW-036`). The update callback's replacement arm —
and only that arm — calls the ABI 16 `focus(node)` host export on the
freshly mounted branch's marked input, so focus moves exactly when the
user's action swapped in an edit affordance; row mount, reorder, and
stable-branch updates never touch focus. Together these express the TodoMVC
edit/view transition with retained row identity:

```lean
component BranchRosterMini (schema := BranchRosterMiniSchema) where {
  state branchAdded : Int := 0;
  event addItem := append roster (s!"Item {branchAdded}", s!"Item {branchAdded}", "view")
    then set branchAdded (branchAdded + 1);
  row roster edit := set mode "edit" then set draft label;
  row roster retype (value : String) := set draft value;
  row roster commit := set label draft then set mode "view";
  region roster (label, draft, mode) := jsx% <li> [
    {if mode == "view"
      then <span> [{label}]
      else <input ariaLabel="Editor" value={draft} onInput={retype} autoFocus/>},
    <span> [<button type="button" ariaLabel="Edit" onClick={edit}> ["Edit"]],
    <span> [<button type="button" ariaLabel="Commit" onClick={commit}> ["OK"]],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
```

Two more delegated kinds close the TodoMVC row vocabulary (ADR-0049).
`onDblClick={name}` binds a payload-less row event as the `dblclick` kind —
unlike row `click` it is permitted on non-button elements, so the label
itself can carry the edit affordance; the delegated dispatch is structural,
so no handler or `tabindex` ever lands on the label. Because a double click
bubbles from any content, it takes `click`'s exact cross-branch agreement
rule: bind the same action in both branch subtrees (typically the editor
input re-binds the same `edit` action, which is harmless when `edit` writes
only the mode field). Keep a keyboard-reachable path to the same action in
the template — a visible button as in `BranchRosterMini`, or a `keydown`
binding — when the interaction must not be pointer-only; the compiler does
not force one, matching TodoMVC's observable DOM. `onChange={name}` on a
`type="checkbox"` input binds a payload-taking row event as the checkbox
`change` kind (`LRX-VIEW-037` on any other element): the delegated `checked`
boolean lowers to the strings `"true"`/`"false"`, so the sealed `String`
update language is unchanged. Pair it with the sealed checked reflection
`checked={done == "true"}` — checkbox inputs only, at most once per element
— so the toggle state survives the retained-row update sweep and appended
rows mount with their `done` state:

```lean
component ToggleRosterMini (schema := ToggleRosterMiniSchema) where {
  state toggleAdded : Int := 0;
  event addItem := append roster (s!"Item {toggleAdded}", "false", "view")
    then set toggleAdded (toggleAdded + 1);
  row roster toggle (checked : String) := set done checked;
  row roster edit := set mode "edit";
  row roster commit := set mode "view";
  region roster (label, done, mode) := jsx% <li> [
    <span> [<input type="checkbox" ariaLabel="Done" checked={done == "true"}
      onChange={toggle}/>],
    {if mode == "view"
      then <span onDblClick={edit}> [{label}]
      else <input ariaLabel="Editor" value={label} onDblClick={edit} autoFocus/>},
    <span> [<button type="button" ariaLabel="Commit" onClick={commit}> ["OK"]],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
```

Whole-region observations and mutations are sealed too (ADR-0050). A
`{count region}` view child renders the region's row count and
`{count region (field == "literal")}` the count of rows whose projected
field equals the literal — text positions mounted at `"0"` (regions mount
empty) and recomputed by the commit sweep whenever the region was touched,
so they track appends, per-row updates, broadcasts, and removals alike. The
predicate is the same single-field `String` equality every sealed selection
uses, so keep the counted field canonical (`done == "false"` counts the
active rows). A count may instead drive a sealed label selection (ADR-0062):
`{if count region == 1 then "one" else "other"}` — either count subject
compared against the one literal — renders one of two static strings, so
TodoMVC's "1 item left" grammar is a text position beside the number. The
label mounts as its `else` string (an empty region counts zero, and zero
differs from one), joins the count inventory as one more slot recomputed by
the same region-touch sweep — riding its own count's read set, and since
ADR-0088 its own count's *pass* — and writes the selected string through the
same `setText` export only on a flip — an equal-selection commit is evaluate-only, and a filter change
alone recomputes nothing. The surface is sealed: the comparison literal is
one and the branches are two static string literals (`LRX-ELAB-127` on any
other threshold or a dynamic branch); every other conditional text stays
rejected (`LRX-VIEW-012`). Two component event steps mutate every row at
once:
`update region (set field (expr), …)` is the region broadcast — the
right-hand sides are sealed row expressions evaluated simultaneously against
each row's current tuple, and the keyed reconcile re-renders every retained
row with its identity, DOM node, and focus preserved — and
`remove region (field == "literal")` keeps only the rows whose field differs
from the literal, disposing exactly the matching rows. A broadcast makes the
region's rows mutable exactly as a `row` update event does. Counts must name
a declared region and field (`LRX-VIEW-038`, `LRX-ELAB-119`); broadcasts and
removals validate their targets and predicates the same way
(`LRX-TYPE-111`/`LRX-TYPE-112`, `LRX-ELAB-119`):

```lean
component CountedRosterMini (schema := CountedRosterMiniSchema) where {
  state countedAdded : Int := 0;
  event addItem := append roster (s!"Item {countedAdded}", "false")
    then set countedAdded (countedAdded + 1);
  event completeAll := update roster (set done "true");
  event clearCompleted := remove roster (done == "true");
  event toggleAll (checked : Bool) := update roster (set done checked);
  row roster toggle (checked : String) := set done checked;
  region roster (label, done) := jsx% <li> [
    <span> [<input type="checkbox" ariaLabel="Done" checked={done == "true"}
      onChange={toggle}/>],
    <span> [{label}]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <button type="button" onClick={completeAll}> ["Complete all"],
    <button type="button" onClick={clearCompleted}
      hidden={count roster (done == "true") == 0}> ["Clear completed"],
    <p> [<strong> [{count roster (done == "false")}],
      {if count roster (done == "false") == 1 then " item left" else " items left"},
      " of ", {count roster}],
    <ul ariaLabel="Items" hidden={count roster == 0}> [<region roster/>],
    <input type="checkbox" ariaLabel="Toggle all"
      checked={count roster (done == "false") == 0} onCheckedChange={toggleAll}/>
  ];
}
```

A static view element may also follow a region's structural emptiness
(ADR-0058): `hidden={count region == 0}` reflects `region`'s *total* row
count against the zero literal into the element's `hidden` boolean
property, so TodoMVC's main and footer sections can hide exactly while the
list is empty. The wrapper mounts hidden — regions mount empty by
construction, the same reasoning that mounts count texts at `"0"` — the
first append reveals it, and removing the last row (a ✕ removal, a guarded
empty commit, or `remove region (…)`) hides it again: the commit sweep
re-evaluates the subject on the same region-touch path the count texts
ride and writes through the existing `setProperty` export only on a flip
of the emptiness. The subject is the row table, not the displayed rows, so
a `filter` hiding every row leaves the section revealed. The subject may
instead be the sealed predicate count (ADR-0059):
`hidden={count region (field == "literal") == 0}` hides the element
exactly while no row satisfies the one row-field-to-string-literal
equality, so TodoMVC's clear-completed button can hide while no row is
done — revealed by the first done toggle, re-hidden when the last done
row untoggles, clears, or is removed, and left revealed by a
`completeAll`-style broadcast. The predicate scan rides the same
region-touch path, attr slot, and boolean cache, so a filter change alone
still re-evaluates nothing. Both subjects are sealed against the zero
literal: other comparison operators, threshold literals, negation,
composition, multiple predicates, and general aggregate expressions are
rejected (`LRX-ELAB-125`), an unknown region or predicate field is
rejected (`LRX-ELAB-119` at the surface, `LRX-VIEW-042` at the model),
and the selection counts as its attribute for duplicate detection
(`LRX-VIEW-001`).

The same region-count boolean may instead be exported as the `checked`
property of a static `type="checkbox"` input (ADR-0060):
`checked={count region (field == "literal") == 0}` checks the box exactly
while no row satisfies the predicate, so TodoMVC's toggle-all checkbox can
be checked exactly while no row is still active. The box mounts checked —
an empty region has no row failing the predicate, the vacuous truth — the
first not-done append unchecks it, a `completeAll`-style broadcast checks
it, and draining the region restores the vacuous truth. The reflection
rides the hidden selection's region-touch path, attr slot, boolean cache,
and `setProperty` export unchanged, and it demands the checkbox input
(`LRX-VIEW-043`) — the `checked` property originates from checkbox inputs
alone, the ADR-0049 rule in static scope. Every other dynamic `checked`
value keeps its meaning (the controlled reflection at component scope, the
row reflection in row templates), and the count-headed shapes are sealed
exactly as `hidden`'s (`LRX-ELAB-125`, `LRX-ELAB-119`). The checkbox's
`onChange` may still name a plain component event — the payload-less
toggle binding, valid only on a checkbox (`LRX-VIEW-043`) — but the
delegated checked payload it discards can instead drive the whole
toggle-all contract (ADR-0061, next paragraph).

Selections of *different* attributes may share one element: duplicate
detection keys on the attribute name (`LRX-VIEW-001`/`LRX-VIEW-021`), so
the toggle-all checkbox can carry `hidden={count region == 0}` beside its
`checked` selection and hide with the rest of the empty-list chrome — the
TodoMVC shape where the toggle-all box and the footer (the counts line and
the filter buttons, wrapped in a `<footer hidden={count region == 0}>`)
disappear together with the empty list. Each selection keeps its own attr
slot, evaluation, and flip-only write, so one appending commit reveals the
whole chrome and the drain of the last row hides it again.

A typed component event may flow its payload into a region broadcast
(ADR-0061): `event toggleAll (checked : Bool) := update region (set field
checked)` is the payload broadcast — the ADR-0050 `update … (set …)` body
whose right-hand side is the bare payload parameter, bound with
`onCheckedChange={toggleAll}` on a checkbox exactly like any ADR-0038
`Bool` event and mounted through the existing `listenChecked` export. The
delegated checked boolean lowers to the `"true"`/`"false"` strings —
the ADR-0049 row-payload downgrade at component scope — so checking
TodoMVC's toggle-all box completes every row and unchecking it un-completes
every row: one transaction, one region touch, the retained rows re-rendered
with identity preserved, and the same commit sweep updating the counts and
every region-count selection together. The vocabulary is sealed tightly:
only the `Bool` checked payload may broadcast (`LRX-ELAB-126` on a `String`
parameter), the payload stands alone on a `set` right-hand side — `trim`,
`++`, comparisons, and every other composition over it are rejected
(`LRX-ELAB-126`) — the other right-hand sides stay sealed payload-free row
expressions, the body is exactly one broadcast (no `then`, no append, no
state write), and the payload appears nowhere else in the component update
language. The model validates the broadcast against the declared region
exactly as ADR-0050's (`LRX-TYPE-116`): a payload broadcast that never
writes its payload is rejected too.

A `filter` item selects which of a keyed region's rows are *displayed*
(ADR-0051): `filter region by field := when "literal" (rowField ==
"literal") then …` maps distinct literals of one `String` component value to
row-field equality predicates, and a state value outside the table — like
TodoMVC's `"all"` — carries no predicate and shows every row. The commit
sweep applies the table after the region's reconcile, whenever the region
was touched or the filter field changed, by writing each row root's
`hidden` property; rows never mount or dispose on a filter change, so row
identity, focus, and the region metrics stay untouched, and counts keep
reading the full row table — `items-left` is filter-independent by
construction. Filters must name a declared region at most once with a
nonempty table over distinct literals and declared row fields
(`LRX-TYPE-113`, `LRX-ELAB-120`):

```lean
component FilteredRosterMini (schema := FilteredRosterMiniSchema) where {
  state filteredAdded : Int := 0;
  state shown : String := "all";
  event addItem := append roster (s!"Item {filteredAdded}", "false")
    then set filteredAdded (filteredAdded + 1);
  event showAll := set shown "all";
  event showActive := set shown "active";
  filter roster by shown := when "active" (done == "false")
    then when "completed" (done == "true");
  row roster toggle (checked : String) := set done checked;
  region roster (label, done) := jsx% <li> [
    <span> [<input type="checkbox" ariaLabel="Done" checked={done == "true"}
      onChange={toggle}/>],
    <span> [{label}]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <button type="button" onClick={showAll}> ["Show all"],
    <button type="button" onClick={showActive}> ["Show active"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
```

Filters distribute per region (ADR-0079). Several regions may each carry
one, and two of them may name the *same* state field: each sweep allocates
its own `filter_scan_{regionIndex}` walk, reads its own container slot
(`5 + counts?2`, computed from that region's own feature set — so two
filtered regions of different widths read different slot numbers), and
wakes on its own `region_touched_{regionIndex} || changed[field]` guard.
One `set` on a shared filter field therefore runs two sweeps inside one
commit, in region declaration order, once each; a region touch and a
filter-field change mixing in one transaction wake their regions for
different reasons and still run in that order. Two filters over *one*
region stay rejected (`LRX-TYPE-113`): a region owns one container and one
row table, so a second table would be two writers of one `hidden` property.

The touch half of that guard is chosen per sweep at elaboration time
(ADR-0082, generalized by ADR-0083). A region's touched flag folds two
events together — the row set changed (structural), or a `row` update queued
a position for the drain — and the second can only move a sweep that reads a
field the drain writes. So *every* sweep over a region is guarded on
`region_structural_{regionIndex}` when its read set is disjoint from the
union of what that region's declared `row` update stages assign — the
ADR-0052 key arms included — and on `region_touched_{regionIndex}`
otherwise. The read sets are fixed by the surface:

| sweep | read set |
| --- | --- |
| `{count r}`, `hidden={count r == 0}` | the row array's length, no field |
| `{count r (f == "x")}`, `hidden={count r (f == "x") == 0}`, `checked={…}` | that one field |
| `filter r by s := …` | every arm predicate's subject fields |
| `persist r := "key"` | every field — so it never narrows |

Adjacent sweeps of one kind that agree share one guarded block, so a region
whose sweeps all read the same flag emits exactly the block it did before
the flag became per sweep. A region with no drain path at all has a provably
empty pending slot, so `touched` and `structural` are the same predicate
there and every sweep keeps the uniform flag. The flag set is therefore
derived per region rather than fixed by the feature list: a region may bind
both flags, one of them, or — when every sweep over it is disjoint from its
drain — only the structural one. What this buys is evaluations, not always
DOM: renaming a row no longer walks every row root to rewrite `hidden` with
the value already there, and no longer runs a predicate scan whose field the
rename cannot touch, but a row total it skips was an `O(1)` comparison.

The write half of that comparison is per row *event* inside the region's own
dispatch function (ADR-0084). `listenDelegatedCells` calls one dispatch per
region, and its `action` argument names the row event that ran — exactly one
action branch executes per call — so there, and only there, a sweep whose
read set only *some* of the region's row events can write is guarded on

```js
    const region_drain_0_0 = regions[0][3] || regions[0][4]["length"] !== 0 && action === "toggle";
```

instead of the region-wide touched flag. An empty event set is still the
structural bit and the whole event set is still the touched flag, so the
extra constants appear only where the row events genuinely disagree, and
every other transaction function keeps the region-wide flags (its pending
slot is provably empty, so there the two are one value anyway). Concretely:
a `row items retype (value : String) := set draft value` beside a
`row items toggle (checked : String) := set done checked` means a keystroke
inside a row editor re-evaluates no count, no `hidden`/`checked` selection
and no filter table — only a `persist` write-back, which reads every field
and can never narrow, still walks the table.

What the write-back *costs* when it walks is narrowed instead, on the row
rather than on the flag (ADR-0085). A persisted region's rows carry one
extra cell behind their declared fields holding that row's serialization,
`null` until it is encoded; the write-back encodes exactly the rows whose
cell is `null` and reads the rest back. Because the cell rides the row
tuple, it is keyed on row identity, so the invalidation is exactly the two
paths that write a field — the row stage, for the row it drained, and the
broadcast, for every row — while `remove`, an `update … remove` predicate
removal and a remove-if guard hit rebuild the row array around unchanged
tuples and therefore re-encode nothing at all. The sweep reports what it
encoded as one trace entry, `storage:{region}:encode:{n}`, so the cache is
observable on a three-row lab. On a 10 000-row region a keystroke's commit
drops from 5.11 ms to 0.59 ms; what remains is the join, the `storageSet`,
and the dispatch's key→position scan. Nothing about the *contract* moves:
one `storageSet` per region-touching transaction, byte-identical stored
values, and no region record slot changed — an unpersisted region's rows
keep their exact shape.

The filter sweep beside it caches the same way and *not* the same way
(ADR-0086). A filtered region's rows carry one more cell — behind the
serialization cell, so a region that is both filtered and persisted lays its
rows out as `[key, f_0, …, f_{n-1}, serial, shown]` — holding the `hidden`
value the sweep last wrote into that row's root, `null` until it writes one.
The sweep evaluates the state-to-predicate table for every row, compares the
result against that cell, and only on a mismatch navigates to the row root
and writes it. The difference from the serialization cell is the one worth
knowing: a row's serialization depends on the row's fields alone, so a write
can stale it, but its displayed state depends on the row's fields **and** the
filter field, so a filter change stales every row at once. There is no
invalidation to write for that, and none is written — the predicate is
recomputed unconditionally (it is pure JS over a row tuple and measured at
0.0% of the commit), and the cell elides only the DOM write. So nothing
anywhere nulls this cell, and every path still ends with the DOM agreeing
with the table: a fresh or hydrated row is born `null` and therefore written
once; `remove`, an `update … remove` predicate removal and a remove-if guard
hit carry survivors' cells along with their untouched nodes and write
nothing; and a filter flip writes exactly the rows that changed side. The
sweep reports what it wrote as `filter:{region}:written:{n}`, and its
`dom:filter:{region}:write` entry now fires only when that number is
nonzero, exactly as an attribute selection's does. On a 10 000-row region a
row toggle's commit drops from 2.47 ms to 0.76 ms; a whole-table flip, where
the cache elides nothing, costs about 8% more.

What is left after those two caches is the *number of walks*, and it is
grouped rather than cached (ADR-0088). Every `{count region (field ==
"literal")}` and every `hidden=`/`checked={count region (field == "literal")
== 0}` over one region is a predicate scan, and two of them share one walk of
the row table exactly when they read the same wake flag — the flag their own
read sets already select. Inside a shared walk each *distinct* field equality
gets one accumulator, so two positions spelling `done == "false"` share a
cell while a `done == "true"` beside them shares only the traversal. Nothing
fuses across a wake class: the pass runs under exactly its class's flag, so a
selection ADR-0084 kept out of a `toggle` is not dragged back in by a
neighbour that woke. A predicate-free `{count region}` is a `length` read,
not a scan, and joins no walk; the filter sweep and the persistence
write-back run after the reconcile and stay their own walks. What is shared
is the traversal and never the cache — every slot keeps its own cache cell,
compare, write, label and counter, in the order it had them — so this is
invisible except in time and in how many times a commit touched the rows. On
a 10 000-row region a row toggle's commit drops from 0.74 ms to 0.61 ms and
walks the table four times instead of seven; a keystroke, which enters no
pass at all, is unchanged.

The last of those walks to go is the dispatch's own (ADR-0092). A row event
starts by resolving the delegated key to a position, and it no longer reads
the table to do it: a module carrying any row event emits one
`$lrx_row_seek(rows, key)` helper — a binary search returning the position or
`-1` — and every region and every branch calls it. Nothing maintains an index
and no region record slot grew, because a row table is already **ordered by
key**: keys come from the region's own `nextKey` counter, which only
increases, they are written once when the row is pushed and never again, and
every removal is order-preserving. That holds for the append, the hydration
that pushes through the same path, every field write, every broadcast, both
predicate removals and the filter sweep — so the "invalidation matrix" a key
index would have owed is, for a search, a table of empty cells. A `remove`
and a remove-if guard hit now `splice` at the resolved position instead of
rebuilding the array behind a kept-filter; the guard hit reuses the position
its own stage already resolved, so it searches once, not twice. On a
10 000-row region a `toggle` walks the table **three** times and a keystroke
**once** — the write-back alone.

That order is checked by the compiler rather than trusted (ADR-0093). Every
module the component backend emits is audited before it is handed back, and
an emission that could disturb a row table's key order is rejected as
`LRX-BE-036` with the rule and the function named: a row entering under
anything but the region's own counter, a `splice` that inserts or removes a
neighbour, a `sort`, an `unshift`, a key slot written, a table aliased into
code the audit cannot see, a counter that rewinds, a region mounted
non-empty, or a whole-table assignment that is not the order-preserving
kept-filter rebuild. Nothing an author writes can trip it — it is a rule
about the emitter, not about the language — and it costs no output bytes and
under two milliseconds per module.

The audit follows a table across calls (ADR-0095). `$lrx_row_seek` receives
`regions[r][1]` as a parameter, and inside the helper the table is no longer
spelled `regions[r][1]` — so the audit computes, before it applies any rule,
which parameters of which functions ever receive a row table, and applies the
same eight rules there. The set is a least fixpoint, so a table forwarded from
one helper to a second is a row table in the second too. Two rules cannot be
satisfied through a parameter and therefore reject: a push needs the region's
own key counter, which a parameter cannot name, and a whole-table rebuild
needs a region slot to install into. A single-row `splice` stays legal, because
it is order-preserving whichever table it is.

The other side of that call is checked as well (ADR-0094). A region host
never writes, reorders, resizes, re-keys or retains the array it is handed:
`update` takes the caller's table, `updateAt` one of its rows, and every
`splice` a host performs is on its own entry array. The region-runtime gate
proves it by handing each host a frozen copy of every caller array and
re-verifying its order and every key slot after each later call, reporting
`LRX-HOST-001` with the rule, the host and the method named.

With the search gone, what is left of a one-row structural commit is the
reconcile itself, and for a removal it is now skipped (ADR-0097). A sealed
single-row removal — the `remove` action, an ADR-0053 guard hit — used to
raise the region's dirty flag, and the commit sweep answered it by handing the
whole table to `update`, which re-runs the generated row-update callback on
every *retained* row: about six DOM operations times N, 4.3–4.7 ms of a 5.5 ms
commit at ten thousand rows, where the key validation, the disposal and
`placeInOrder` together are under 0.3 ms. The dispatch already knows which
position it removed, so it now queues `[position, key]` in the region record's
last slot and the commit sweep drains it through the region handle's
`removeAt` — one disposal, one detach, and every survivor's DOM node and
row-update callback left alone. A single-row removal at ten thousand rows is
**2.9×–4.3×** faster and the host's update counter does not move at all. Three
things travel with it. The drain runs *before* the reconcile, not instead of
it, so a transaction that also appends still reconciles. It runs before the
filter sweep, which navigates by row-table position and needs the DOM back in
step. And every wake flag that read the dirty bit as "the row set moved" reads
the queue beside it, so the counts, the emptiness sweeps, the filter table and
the write-back still run on a removal. Two removals keep the reconcile on
purpose: an `update … remove` predicate removal, whose row count is unbounded
and whose all-rows case the reconcile clears in bulk, and `append`, which has
no host counterpart because mounting a row is `update`'s alone.

A `route` may target a filter field that several regions share (ADR-0080).
The field's sealed state literals are then the declared default plus the
**union** of every filter table over that field, not the first-declared
table's: below, `"mixed"` is named by `right` alone, and `#/mixed` is a
legal route arm on the strength of that table even though `left` is
declared first. The union is what the emission already means — the routed
field is component-wide, one `hashchange` raises the one changed bit both
sweeps are guarded on, and a literal one table omits is simply that
region's fall-through to show-all — so a first-match reading would make a
`LRX-TYPE-117` rejection depend on declaration order. `writeHash` still
rides the routed field's own changed flag once per commit, however many
regions filter on it. One of the regions a routed field drives may also
carry a `persist` item without the two interacting (ADR-0081): the
persistence sweep is guarded on that region's touched flag alone, so a
route flip runs both sweeps and writes nothing to storage, and a row
touch writes storage and no hash.

```lean
component TwinFilterMini (schema := TwinFilterMiniSchema) where {
  state twinMode : String := "all";
  state twinTone : String := "all";
  event showOn := set twinMode "on";
  event toneOn := set twinTone "on";
  filter left by twinMode := when "on" (flag == "true");
  filter right by twinMode := when "on" (flag == "false")
    then when "mixed" (flag == "true");
  filter solo by twinTone := when "on" (flag == "true");
  route twinMode := when "#/" "all" then when "#/on" "on"
    then when "#/mixed" "mixed";
  persist right := "leanrx-guide.twin-right";
  region left (label, flag) := jsx% <li> [<span> [{label}], <span> [{flag}]];
  region right (label, flag) := jsx% <li> [<span> [{label}], <span> [{flag}]];
  region solo (label, flag) := jsx% <li> [<span> [{label}], <span> [{flag}]];
  view := jsx% <main> [
    <button type="button" onClick={showOn}> ["Show on"],
    <button type="button" onClick={toneOn}> ["Tone on"],
    <ul ariaLabel="Left"> [<region left/>],
    <ul ariaLabel="Right"> [<region right/>],
    <ul ariaLabel="Solo"> [<region solo/>]
  ];
}
```

A `route` item seals the browser's URL hash onto the filter field
(ADR-0063): `route field := when "#/hash" "literal" then …` maps distinct
`#/`-shaped hash literals one-to-one onto the routed field's existing state
literals — the declared default plus the literals of every ADR-0051 filter
table over that field (ADR-0080), on a `String` state field that must carry
at least one declared filter. Exactly one arm
maps the declared default, so the unknown-or-empty-hash fallback is a table
entry rather than a separate path: mount seeds the field through one
`readHash` (an unknown hash keeps the declared default), every `hashchange`
dispatches the same set-field transaction the filter buttons dispatch — the
whole commit path reused, selection, filter sweep, and count labels included
— and `writeHash` rides the set-field commit flip-only behind the field's
changed flag, so an equal-value transaction writes nothing and the WHATWG
equal-value hash assignment closes the echo loop. Arms are written
`when "#/hash" "literal"` (`LRX-ELAB-128` on any other arm shape); the table
rules — at most one route item per component, a `String` state field
carrying at least one declared filter, a nonempty one-to-one table of
distinct `#/`-shaped hash literals over the field's existing state literals
(the declared default and every filter table over the field), exactly one
arm on the declared default — are `LRX-TYPE-117`.

The one-route cap is the sharpest of those, and it is a property of the
hash rather than of the emission (ADR-0081). Two route items generate
cleanly — arms, dispatch chain, mount seed, and hash write are all indexed
by route — but `location.hash` is one string with one writer, and a route
table is a *total* function from that string onto its field's literals, so
two tables are two total functions over one string and the loser is not
merely ignored: an unknown hash falls to a route's default arm, so
whatever the other route wrote resets this route's field. Concretely, two
`if (changed[field])` write blocks race inside one commit and the last one
wins, and one `hashchange` wakes both dispatches in registration order
with the second reading the hash the first just rewrote. A single click
that means to change one field ends with both fields back at their
declared defaults. Lifting the cap would need either disjoint hash
sub-namespaces with partial tables — changing the unknown-hash fallback
every route rests on — or one table over the tuple of routed fields, which
is a single route item over a wider field:

```lean
component RoutedRosterMini (schema := RoutedRosterMiniSchema) where {
  state routedAdded : Int := 0;
  state routedShown : String := "all";
  event addItem := append roster (s!"Item {routedAdded}", "false")
    then set routedAdded (routedAdded + 1);
  event showAll := set routedShown "all";
  event showActive := set routedShown "active";
  event showCompleted := set routedShown "completed";
  filter roster by routedShown := when "active" (done == "false")
    then when "completed" (done == "true");
  route routedShown := when "#/" "all" then when "#/active" "active"
    then when "#/completed" "completed";
  row roster toggle (checked : String) := set done checked;
  region roster (label, done) := jsx% <li> [
    <span> [<input type="checkbox" ariaLabel="Done" checked={done == "true"}
      onChange={toggle}/>],
    <span> [{label}]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <button type="button" onClick={showAll}> ["Show all"],
    <button type="button" onClick={showActive}> ["Show active"],
    <button type="button" onClick={showCompleted}> ["Show completed"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
```

A `persist` item seals a keyed region's row table onto one localStorage key
(ADR-0063): `persist region := "storage-key"` declares one sealed literal
key per persisted region, targeting one declared keyed region. A component
may persist several regions, each under its own key (ADR-0078). Serialization lives
in generated code as a throw-free split/join escape — `%`→`%25` first, then
`,`→`%2C` and `;`→`%3B`; fields joined by `,`, rows by `;` — so no decode
step can throw. Mount hydrates each persisted region through its own `storageGet` as one
ordinary transaction whose writes push the parsed rows through the existing
append path, so the shared commit sweep settles rows, counts, visibility,
filter, and the normalized write-back together; the hydrate transactions run
in persist declaration order, each settling the whole sweep before the next
begins. A missing or empty value mounts that region empty, and any row whose
field count differs from the declared arity fails the whole value closed to
the empty region. One `storageSet` rides the region-touch sweep per
region-touching transaction — the ADR-0050/0051/0058 shared touched flag —
so a filter change alone touches nothing and therefore persists nothing, and
a transaction touching one of two persisted regions rewrites that region's
key alone. *When* that write lands is a contract and not an implementation
detail (ADR-0087): the `storageSet` runs inside the commit sweep,
synchronously, before the dispatch that opened the transaction returns, and
nothing is deferred, batched, or coalesced across transactions. So a read of
the key — by hydration, by another component, by another tab, or by the same
task immediately after a dispatch — observes what the last completed commit
wrote; N dispatches inside one task (a synchronous `click()` burst, say)
write N times, and a re-read between any two of them sees the earlier one.
Nesting coalesces the commit and not the flush: transactions nested through
the transaction depth counter produce one commit and therefore one write.
The consequence a per-task flush would take away is that a tab closed at any
moment loses nothing a returned dispatch wrote, so no component that persists
a region owes an unload hook or a lost-write recovery path.

*What* that write costs is written down too (ADR-0096), because it is the
component's to control and not the compiler's. Per region-touching
transaction, per persisted region the transaction touched, a commit pays
about 5 µs of fixed `storageSet` cost, about 0.85 ns per byte of that
region's table, and about 18 ns per row to join it. The two are different
functions, not two halves of one floor: the host term has no row component
(it is handed a string, and a string is all it knows) and the join term has a
byte component an order of magnitude smaller, so they are equal only at about
twenty-three bytes per row and diverge in either direction from there. The
payload is the component's own bytes — the encoding adds one field separator
between each pair of a row's declared fields and one row separator between
rows and nothing else, so there is no per-row key, position index, length
prefix or version tag being paid for — which means the two levers are
*narrower rows* and *fewer rows*, and neither is one the compiler can pull,
since a field's value is an opaque
string it may not shorten. A component persisting several regions pays the
fixed term once per region a commit touched, not once per transaction. Moving
the join, or the whole sweep, behind a host export that takes the segment
array or the row table was measured at 0.99×–1.10× and declined: the same N
segments and the same bytes cross the boundary either way. Writing part of
the table under chunked keys is the only shape that writes fewer bytes per
commit, and it would withdraw the visibility sentence above — `localStorage`
has no multi-key transaction, so another tab could observe one chunk of a
commit and not the next. The item shape — a declared region name, exactly one literal
storage key — is `LRX-ELAB-129`; one persist item per region, keys distinct
across the component, each nonempty and on a declared region, is
`LRX-TYPE-118` (two items on one region, or two regions sharing one key,
would make one commit sweep's two write-backs race for one slot). The
nonempty rule is not a shape check: `""` is a perfectly legal localStorage
key — the browser stores under it, enumerates it, and hands it back — so an
empty key produces no error at all, just an origin-wide slot that every
other unnamed writer shares. Hydration cannot recover, because a foreign
value with this region's field arity parses as this region's own rows and
is then re-persisted as such; the key is the whole namespace guarantee, so
the empty one is rejected where it is written (ADR-0082):

```lean
component PersistedRosterMini (schema := PersistedRosterMiniSchema) where {
  state persistedAdded : Int := 0;
  event addItem := append roster (s!"Item {persistedAdded}", "false")
    then set persistedAdded (persistedAdded + 1);
  event clearCompleted := remove roster (done == "true");
  persist roster := "leanrx-language-guide.roster";
  row roster toggle (checked : String) := set done checked;
  region roster (label, done) := jsx% <li> [
    <span> [<input type="checkbox" ariaLabel="Done" checked={done == "true"}
      onChange={toggle}/>],
    <span> [{label}]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <button type="button" onClick={clearCompleted}> ["Clear completed"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
```

Both vocabularies are the runtime ABI 17 host surface (`readHash`,
`listenHash`, `writeHash` for routing; `storageGet`, `storageSet` for
persistence — the host moves strings only), and both are reachability-gated
in the import emission: a component declaring no route or persist item
emits a byte-identical module.

A keydown row event may *branch* on its key payload (ADR-0052):
`row region event (pressed : String) := when "Enter" (set field (expr), …)
then when "Escape" (…)` lowers to a sealed key table — the declared
parameter is the discriminant, named in the head and compared implicitly by
each arm, the filter-table shape in row scope. A matched arm performs its
simultaneous assignments as one retained-row update; a key outside the table
is a no-op (no row scan, no update, no trace), which is what makes an
Enter-only commit expressible. Key literals come from the sealed
`Enter`/`Escape` set, each at most once; arm right-hand sides are
payload-free (the key literal already fixes the payload); and the event
binds through `onKeyDown` exactly once on a native input — all
`LRX-VIEW-039`, with `LRX-ELAB-121` pinning the surface (a `when` arm needs
the declared parameter and mixes with no other steps). The equality runs
inside the generated dispatch function over the delegated `key` argument, so
there is no host change and no ABI bump:

```lean
component KeyedEditorMini (schema := KeyedEditorMiniSchema) where {
  state keyedAdded : Int := 0;
  event addItem := append roster (s!"Item {keyedAdded}", s!"Item {keyedAdded}", "view")
    then set keyedAdded (keyedAdded + 1);
  row roster edit := set mode "edit";
  row roster retype (value : String) := set draft value;
  row roster keys (pressed : String) := when "Enter" (set label draft, set mode "view")
    then when "Escape" (set draft label, set mode "view");
  region roster (label, draft, mode) := jsx% <li> [
    {if mode == "view"
      then <span onDblClick={edit}> [{label}]
      else <input ariaLabel="Editor" value={draft} onInput={retype}
        onKeyDown={keys} onDblClick={edit} autoFocus/>}
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
```

Enter commits (`label := draft`, back to the view branch) and Escape reverts
(`draft := label` restores the pre-edit text, since `label` changes only on
commit), so the next edit entry opens pre-filled with the restored draft
through the value reflection.

A row stage may carry a *remove-if guard* (ADR-0053):
`row region event := if field == "literal" then remove else
(set field (expr), …)` — and the same `if` shape inside a `when` key arm —
compares one row field against one string literal when the event dispatches.
A guard hit removes the dispatching row through the same positional
`removeAt` drain the sealed `remove` action uses (ADR-0097), reusing the
position its own stage already resolved; a miss commits the else-steps
exactly as an unguarded stage does. This is what makes TodoMVC's
destroy-on-empty-commit expressible: guard both commit paths with
`draft == ""` and an empty draft's Enter (or OK click) destroys the row
while a nonempty draft commits. The guard is the whole predicate language —
one field, one literal, `String` equality, no negation or conjunction, and
no payload or component state — and a guarded stage stands alone (no other
steps beside it) with `remove` as its only hit. The guard subject may sit
behind the `trim` unary (ADR-0054): `if trim draft == "" then remove else
(set label (trim draft), …)` removes on a whitespace-only draft and stores
the committed label trimmed — TodoMVC's trim contract, expressed by the
expression vocabulary rather than a wider guard shape (any other guard
subject expression is rejected). The guard field must be in bounds and a
guarded plain event is payload-less (`LRX-VIEW-040`), with `LRX-ELAB-122`
pinning the surface. The equality runs inside the generated dispatch
function against the row the existing key search resolved, so once more there
is no host change and no ABI bump:

```lean
component GuardedEditorMini (schema := GuardedEditorMiniSchema) where {
  state guardedAdded : Int := 0;
  event addItem := append roster (s!"Item {guardedAdded}", s!"Item {guardedAdded}", "view")
    then set guardedAdded (guardedAdded + 1);
  row roster edit := set mode "edit";
  row roster retype (value : String) := set draft value;
  row roster commit := if trim draft == "" then remove
    else (set label (trim draft), set mode "view");
  row roster keys (pressed : String) :=
    when "Enter" (if trim draft == "" then remove
      else (set label (trim draft), set mode "view"))
    then when "Escape" (set draft label, set mode "view");
  region roster (label, draft, mode) := jsx% <li> [
    {if mode == "view"
      then <span onDblClick={edit}> [{label}]
      else <input ariaLabel="Editor" value={draft} onInput={retype}
        onKeyDown={keys} onDblClick={edit} autoFocus/>},
    <span> [<button type="button" ariaLabel="OK" onClick={commit}> ["OK"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
```

Escape stays unguarded by choice: reverting an empty draft restores the
label instead of destroying the row.

A component event may carry a *skip-if guard* (ADR-0055): `event add := if
trim draft == "" then skip else (append roster (trim draft), set draft
"");` compares one `String` state field — raw or behind the `trim` unary,
which staged `rx%` expressions now share with row scope (`trim field` or
`trim (expr)`, ASCII whitespace stripped from both ends and emitted as the
same `asciiTrimPattern` replace) — against the empty string literal when
the event dispatches. A guard hit makes the whole event a no-op before the
transaction begins: no write, no append, no dispatch, and no trace. A miss
runs the else-steps as one ordinary transaction. The empty literal is the
entire predicate language — no other literal, no negation, no conjunction,
and the sealed `skip` is the only hit — TodoMVC's add contract, not a
conditional event vocabulary. Together with a controlled input (ADR-0038)
this closes ADR-0054's component-scope gap: "a whitespace-only Add is
ignored; a valid draft appends the trimmed label and resets the draft". The
guard subject must be a `String` source (`LRX-TYPE-114`), with
`LRX-ELAB-123` pinning the surface:

```lean
component NewTodoMini (schema := NewTodoMiniSchema) where {
  state newTodoDraft : String := "";
  event add := if trim newTodoDraft == "" then skip
    else (append roster (trim newTodoDraft), set newTodoDraft "");
  event setDraft (value : String) := set newTodoDraft value;
  event confirm (pressed : String) :=
    when "Enter" (if trim newTodoDraft == "" then skip
      else (append roster (trim newTodoDraft), set newTodoDraft ""));
  region roster (label) := jsx% <li> [
    <span> [{label}],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
  ];
  view := jsx% <main> [
    <input ariaLabel="New todo" value={rx% newTodoDraft} onInput={setDraft}
      onKeyDown={confirm}/>,
    <button type="button" onClick={add}
      disabled={trim newTodoDraft == ""}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
```

A payload-taking component event whose steps are `when "key" (…)` arms is a
*key-branched event* (ADR-0056): the ADR-0052 sealed key selection lifted to
component scope. The declared `String` parameter is the discriminant, named
in the head, compared implicitly by each arm, and not spellable inside an
arm body — the matched literal already fixes it. Key literals come from the
sealed `Enter`/`Escape` set, each at most once, and every arm body is an
ordinary component step sequence, optionally behind the skip-if guard — so
`confirm` above makes Enter run exactly the Add button's guarded add. The
event binds through `onKeyDown` exactly once on a native input and rides
the same `listenKey` host adapter typed key payloads always used; a key
outside the arm table is a whole-event no-op before any transaction exists.
`LRX-TYPE-115` seals the arm table, `LRX-VIEW-041` the binding, and
`LRX-ELAB-124` the surface.

A static view element may select its `class`, `aria-pressed`, or `disabled`
from component state (ADR-0045):
`class={if filter == "all" then "selected" else ""}` selects between two
static class strings, `ariaPressed={filter == "all"}` reflects the equality
as `"true"`/`"false"`, and `disabled={filter == "all"}` reflects it as the
boolean element property. The predicate is equality of one `String`
component value (source or derived) against one string literal; the field
reference is the ordinary schema `Field`, so a non-`String` field is a plain
Lean type error. The subject may sit behind the one sealed `trim` unary
(ADR-0057) — `disabled={trim newTodoDraft == ""}` above grays the Add
button on exactly the ASCII-trimmed equality its skip guard evaluates, so
the affordance agrees with the dispatch-layer contract by construction
(and only the guard *is* the contract: the event stays a no-op wherever it
is triggered from). General predicates, negation, and composed subjects
are not selections. Selections join the commit sweep beside text sinks and
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

A parent that itself declares immutable props may forward one into a child
prop (ADR-0068): `<TitledMini title={heading}/>` passes the parent's own
`heading` prop — the value the parent received at mount, still a mount-time
constant — and the generated call reads the parent's positional mount
argument (`$lrx_child_0(node, [props[0]])`). The forwarded value is exactly
one declared prop identifier: concatenation, interpolation, `rx%` staging,
and state or derived references are not forwardable (reactive child props
would contradict the immutable-prop contract), a root component without
props has nothing to forward, and forwarding into a head without a checked
spec reports `LRX-ELAB-130`:

```lean
component PropForwardMini (schema := PropForwardMiniSchema) where {
  state forwards : Int := 0;
  prop heading : String;
  event host := set forwards (forwards + 1);
  view := jsx% <main> [
    <button type="button" onClick={host}> ["Host"],
    <TitledMini title={heading}/>
  ];
}
```

A reference whose shape leaves this contract while the child's checked
spec *is* in scope — children on the reference, a composed value such as
`tag={heading ++ "!"}`, or any non-prop attribute the sugar does not
claim — is rejected with `LRX-ELAB-132` at the head (ADR-0073), naming
the child-reference contract instead of the raw `Unknown identifier`
the typed-application fallback would otherwise produce. A capitalized
head without a checked spec keeps its ordinary typed-application
meaning unchanged (ADR-0039) — for its attributes: the application
never consumes JSX children, so non-empty children on a spec-less head
are rejected with `LRX-ELAB-133` instead of vanishing silently
(ADR-0074). The logical reference view shares both guards — a checked
component reference there reports `LRX-ELAB-132` (checked components
nest in the typed view only), a spec-less application with children
`LRX-ELAB-133`, and a spec-less application without children keeps its
ordinary meaning. Prop-name or order mismatches on a well-shaped
reference stay `LRX-ELAB-112`.

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

LeanRx does not currently provide a general URL router — routing is the
sealed one-per-component hash route table over one filtered state field
(ADR-0063, ADR-0080),
nothing wider — general VDOM, arbitrary Lean transpilation, raw HTML, URL
attributes, a CSS DSL, SSR, hydration, a released package, or a formal proof
relating generated JavaScript to browser DOM behavior.
The self-hosted documentation site records how these gaps affect a real build.
