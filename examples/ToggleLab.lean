import LeanRx

/-! Toggle Lab dogfoods the two ADR-0049 delegated row event kinds through
the generic component backend: TodoMVC's remaining row interactions on top
of the ADR-0047 branch cell and the ADR-0048 focus transfer. Double-clicking
an item's label enters the edit branch — `onDblClick={edit}` is the
payload-less `dblclick` kind, permitted on the non-button label because the
delegated dispatch is structural (no handler or tabindex ever lands on the
label element itself) — and the checkbox toggles the row's `done` field:
`onChange={toggle}` on the `type="checkbox"` input is the `checkedChange`
kind, whose delegated `checked` boolean lowers to the `"true"`/`"false"`
string payload, so `row items toggle (checked : String) := set done checked`
keeps the sealed `String` update language unchanged. Both kinds ride the
existing `listenDelegatedCells` export — two more listener registrations and
two more static action arrays, no host change and no runtime ABI bump.

The label dblclick takes `click`'s exact cross-branch agreement rule, so the
edit branch binds the same `edit` action on the editor input; because
`draft` mirrors `label` outside editing (rows append with `draft = label`
and commit writes `label := draft`) and `edit` only writes `mode`, a
dblclick inside the editor is an update no-op that cannot clobber the draft
(the ADR-0038 equal-value caret no-op keeps the caret in place). The
checkbox carries the sealed row checked reflection
(`checked={done == "true"}`, the ADR-0045 `disabled` shape in row scope), so
the toggle state survives the retained-row update sweep, appended rows mount
with their `done` state, and the delegated `change` is itself an equal-value
no-op on the checkbox it originated from. The row root's class selection
follows `done`, pinning that the toggle drains one retained-row `updateAt`
with row identity preserved.

The lab also dogfoods the ADR-0050 aggregates and broadcasts. The items-left
line carries both sealed count forms — `{count items (done == "false")}` is
the predicate count and `{count items}` the row total — recomputed by the
commit sweep whenever the region was touched and written through the
existing `setText` export. `completeAll` is a region broadcast
(`update items (set done "true")`): every row's `done` takes the sealed row
expression and the dirty reconcile re-renders every retained row — checkbox
and class selection follow with row identity preserved. `clearCompleted` is
the predicate removal (`remove items (done == "true")`): the reconcile
disposes exactly the done rows and the survivors keep their DOM nodes. All
three ride the existing region record and `update(items)` path — no host
change and no runtime ABI bump.

The ADR-0051 filter view selects which rows are displayed:
`filter items by filter := when "active" (done == "false") then
when "completed" (done == "true")` maps the `filter` state literals to
row-field equality predicates, and the unmatched `"all"` shows every row.
The commit sweep applies the table after the reconcile and drain — whenever
the region was touched or `filter` changed — through the region handle's
`setDisplayed(position, key, displayed)`, which takes a deselected row out
of the container and puts it back at its table position (ADR-0102; ADR-0101
priced writing `hidden` on it instead and this is 8.3× on the real flip at
ten thousand rows). Rows never mount or dispose on a filter change, so row
identity, focus, and the region metrics stay untouched, and the counts keep
reading the full row table — `items-left` is filter-independent by
construction.

The ADR-0052 key-branched row event closes the editor's keyboard loop:
`row items keys (pressed : String) := when "Enter" (…) then when "Escape"
(set draft label, set mode "view")` binds `onKeyDown={keys}` beside
`retype` — the declared parameter is the discriminant, named in the head and
compared implicitly by each arm, the ADR-0051 filter-table shape in row
scope. Enter commits the draft exactly as the OK button does; Escape
restores the draft from the pre-edit label (the retype writes are discarded,
and the next edit entry reflects the restored draft through the ADR-0047
value reflection); a key outside the sealed Enter/Escape set is a no-op —
no row scan, no `updateAt`, no region trace. The equality branches run
inside the generated dispatch function over the `eventKey` argument
`listenDelegatedCells` has passed since ABI 15, so once more: no host change
and no runtime ABI bump.

The ADR-0053 remove-if guard completes the editor with TodoMVC's
destroy-on-empty-commit: both commit paths — the OK button's `commit` event
and the Enter key arm — carry `if draft == "" then remove else (set label
draft, set mode "view")`, the sealed single-field guard whose hit removes
the dispatching row through the same kept-filter the ✕ button's `remove`
runs, and whose miss commits the assignments exactly as before. The guard
equality is evaluated inside the generated dispatch function against the
row resolved by the existing key scan, so a nonempty draft's commit is
byte-for-byte the unguarded sequence and an empty draft's Enter (or OK)
disposes the row through the ordinary dirty reconcile — row identity of the
survivors preserved. Escape stays unguarded: reverting an empty draft
restores the label instead of destroying the row. Still no host change and
no runtime ABI bump.

The ADR-0054 trim unary completes TodoMVC's trim contract on both commit
paths: the guard compares the trimmed draft — `if trim draft == "" then
remove else (set label (trim draft), set draft (trim draft), set mode
"view")` — so a whitespace-only draft's Enter (or OK) removes the row
exactly as an empty one does, and a committed label is stored trimmed
(`" x "` commits as `"x"`). The commit re-mirrors the draft to the same
trimmed value, keeping the draft-mirrors-label invariant intact: the next
edit entry starts from the stored label, exactly as TodoMVC's editor does.
`trim` is a row-expression vocabulary extension, not a guard extension: the
guard stays one single-field equality whose subject may sit behind the one
sealed unary, and the commit assignments evaluate the same expression
through the same `rowExprJs` lowering. The emitted strip is the
ASCII-whitespace replace the hand-written Todo backend has always used —
aligned with Lean's `String.trim`, not the Unicode-aware
`String.prototype.trim`. Escape's revert arm remains untrimmed and
unguarded: it restores the pre-edit label verbatim. Once more: no host
change and no runtime ABI bump.

The ADR-0055 component-scope add path closes ADR-0054's first open
question: the new-todo `draft` is component state mirrored into a
controlled input (`value={rx% draft}` with the per-keystroke `setDraft`
typed event — the ADR-0038 path), and `addTodo` is a guarded component
event: `if trim draft == "" then skip else (append items (trim draft, trim
draft, "false", "view"), set draft "")`. The sealed skip-if guard makes a
whitespace-only draft's Add a whole-event no-op — the generated dispatch
function returns before the transaction begins, so there is no write, no
append, no trace, and no region touch — while a valid draft appends one row
with the ASCII-trimmed label (the row draft mirrors it, ADR-0043) and
resets the component draft through the same transaction. `trim` here is the
`RxExpr` unary riding the ADR-0054 `asciiTrimPattern` emission through the
ordinary scalar evaluators; the guard subject rides the same emission
inline. Still no host change and no runtime ABI bump.

The ADR-0056 key-branched component event closes ADR-0055's Enter-to-add
gap: `confirmAdd (pressed : String) := when "Enter" (if trim draft == ""
then skip else (append items (…), set draft ""))` is the ADR-0052 sealed
key selection lifted to component scope, bound as `onKeyDown={confirmAdd}`
on the same new-todo input beside the per-keystroke `setDraft`. The
declared parameter is the discriminant, named in the head, compared
implicitly by each arm, and not spellable inside an arm body; key literals
come from the sealed Enter/Escape set; and each arm body is an ordinary
component step sequence optionally behind the ADR-0055 skip guard — so
Enter runs exactly the Add button's guarded add contract: a whitespace-only
draft's Enter returns before any transaction exists (no write, no append,
no trace), a valid draft appends the trimmed label and resets the draft,
and any other key returns from the dispatch function without touching the
context at all. The dispatch rides the existing `listenKey` export the
delegated `key` payload has always used, so once more: no host change and
no runtime ABI bump.

The ADR-0057 trimmed attribute selection closes ADR-0055's third open
question — the Add affordance: `disabled={trim draft == ""}` is the
ADR-0045 sealed `disabled` selection whose subject sits behind the one
ADR-0054/0055 trim unary, so the Add button grays exactly when the
dispatch-layer skip guard would hit — the same ASCII-trimmed equality,
riding the same `asciiTrimPattern` emission through the commit sweep's
evaluate-compare-write shape and the existing `setProperty` export. The
button mounts disabled (the draft starts empty), stays disabled across
whitespace-only typing, enables on the first non-whitespace character, and
re-disables when the guarded add resets the draft. The affordance is not
the contract (ADR-0055 rejection 2 stands): the skip guard keeps both
dispatch paths total no-ops wherever they are triggered from, and the
disabled property is only the sweep's reflection of that same equality.
Still no host change and no runtime ABI bump.

The ADR-0058 empty-region visibility closes TodoMVC's hide-when-empty
parity: `hidden={count items == 0}` on the items list wrapper is the sealed
region-subject attribute selection — the wrapper's `hidden` boolean
property reflects emptiness of the region's row table, the total row count
against the zero literal and nothing else. The wrapper mounts hidden
(regions mount empty by construction, the ADR-0050 `"0"` reasoning), the
first append reveals it, and removing the last row — ✕, an empty commit,
or clearCompleted — hides it again: the commit sweep re-evaluates the
subject on the same region-touch path the count texts ride, compares it
against the shared attr cache slot, and writes through the existing
`setProperty` export with the shared `attr:{index}:hidden` labels and
tx[8]/tx[9] counters. Because the subject is the row table and not the
displayed rows, an ADR-0051 filter hiding every row leaves the wrapper
visible — visibility is structural emptiness, not filtered emptiness.
Once more: no host change and no runtime ABI bump.

The ADR-0059 predicate-count visibility closes ADR-0058's first open
question — the clear-completed affordance:
`hidden={count items (done == "true") == 0}` on the Clear completed button
is the sealed hidden selection whose subject is the ADR-0050 predicate
count — the number of rows whose `done` field equals `"true"` — against
the same zero literal. The button mounts hidden (an empty region satisfies
no predicate), the first done toggle reveals it, and draining the done
rows — untoggling the last one, `clearCompleted` itself, or removing the
row — hides it again: the commit sweep runs the ADR-0050 predicate scan on
the same region-touch path, compares against the same shared attr cache
slot, and writes through the same `setProperty` export. A filter change
alone still re-evaluates nothing (the region is untouched), and the
`completeAll` broadcast leaves the button revealed — every row is done.
The `hidden` selection is valid on any static element, the button
included (only `aria-pressed` and `disabled` demand a native button, and
a button satisfies even that). Once more: no host change and no runtime
ABI bump.

The ADR-0060 toggle-all checked reflection closes the display half of
TodoMVC's toggle-all parity: `checked={count items (done == "false") == 0}`
on the static toggle-all checkbox is the sealed checked selection whose
subject is the same region-count boolean the hidden selections read —
here the ADR-0050 predicate count of not-done rows against the zero
literal — exported into the `checked` property instead of `hidden`. The
box mounts checked (an empty region has no row failing the predicate —
vacuously all complete), the first not-done append unchecks it, the
`completeAll` broadcast checks it, untoggling a done row or appending
unchecks it again, and `clearCompleted` draining the region restores the
vacuous truth. The sweep is byte-for-byte the hidden selections': the
same region-touch path, shared attr slot, boolean cache, and `setProperty`
export with `attr:{index}:checked` labels — a filter change alone still
re-evaluates nothing. The selection demands a static `type="checkbox"`
input (the ADR-0049 origin rule in static scope). Once more: no host
change and no runtime ABI bump.

The ADR-0061 payload broadcast closes the action half — the uncheck path
ADR-0060 left unrepresentable: `toggleAll (checked : Bool) := update items
(set done checked)` is a typed component event whose body is one ADR-0050
region broadcast carrying the delegated `checked` payload as a bare `set`
right-hand side, lowered to the `"true"`/`"false"` strings exactly as the
ADR-0049 row payload is. The box binds it through the ADR-0038
`onCheckedChange` surface, riding the existing `listenChecked` form-event
export, so checking the box completes every row (each checkbox follows
through its ADR-0049 reflection and the box re-checks through its
ADR-0060 selection) and unchecking it un-completes every row — the
sweep's evaluate-compare-write agrees with the browser's own uncheck, so
the ADR-0060 cache-DOM divergence is gone. One broadcast's region touch
updates the items-left counts, the clear-completed hidden, the list
hidden, and the toggle-all checked together; an equal-payload broadcast is
an evaluate-only sweep; an empty-region broadcast touches no row and
writes nothing; and a filter change alone still re-evaluates nothing.
The payload stands alone on its right-hand side (no trim, no
concatenation, no comparison), the body is exactly one broadcast, and only
the Bool checked payload may broadcast. Once more: no host change and no
runtime ABI bump.

The ADR-0062 count label closes TodoMVC's items-left grammar: `{if count
items (done == "false") == 1 then " item left" else " items left"}` is the
sealed count-driven text selection — the ADR-0050 count subject, total or
predicate, compared against the one literal, selecting between two static
strings at a text position. The label joins the count inventory as one more
slot: it mounts as the `else` string (an empty region counts zero, and zero
differs from one), the commit sweep recomputes it on the same region-touch
path with the same per-slot scan the count texts run (no scan sharing —
ADR-0050 already re-scans per position), and the selected string rides the
same cache compare and the existing `setText` export, so the first append
flips the line to "1 item left" in one evaluation and one write, the second
flips it back to plural, and every broadcast, toggle, ✕ removal, and
clearCompleted updates the number and the label in the same commit. An
equal-selection commit is evaluate-only, and a filter change alone still
recomputes nothing. The comparison literal is sealed at one, the branches
are static string literals, and every other conditional text stays
rejected. Once more: no host change and no runtime ABI bump.

Two contracts the vocabulary already carries run here without any grammar
change — a lexicon-invariant execution round, not an ADR. First, TodoMVC's
main/footer hide-when-empty parity: the toggle-all checkbox takes
`hidden={count items == 0}` beside its `checked` selection (two selections
of *different* attributes on one element — the ADR-0045 duplicate detection
keys on the attribute name, so they share the element and the attr sweep
without conflict), and the items-left line plus the three filter buttons
move into a `<footer hidden={count items == 0}>` — the ADR-0058 emptiness
subject reused verbatim on two more slots. Both mount hidden, the first
append reveals them in the same commit as the list wrapper (one evaluation
and one write per attr slot), removing the last row re-hides them, and an
ADR-0051 filter hiding every displayed row leaves them visible — structural
emptiness, not filtered emptiness. Second, the new-todo Escape revert:
`confirmAdd` gains the `when "Escape" (set draft "")` arm — the sealed
Enter/Escape component key set held Escape spellable but unexecuted until
now. The arm is unguarded, so Escape commits unconditionally: the draft
clears, the controlled input follows to `""`, the Add button re-disables
through its ADR-0057 reflection, and a subsequent Enter hits the skip guard
as a whole-event no-op. Any other key still returns without touching the
context. Once more: no host change and no runtime ABI bump.

The ADR-0063 execution round closes the last TodoMVC parity axis — URL
routing and localStorage persistence — as the one runtime ABI 17 bump: five
sealed DOM-host exports (`readHash`, `listenHash`, `writeHash`, `storageGet`,
`storageSet`) under the ADR-0048 pruning condition. `route filter := when
"#/" "all" then when "#/active" "active" then when "#/completed" "completed"`
maps the sealed `#/`-shaped hash literal set one-to-one onto the filter
field's existing state literals: mount seeds the field through one `readHash`
(an unknown or empty hash keeps the declared `"all"` default), every
`hashchange` dispatches the same set-field transaction the filter buttons
dispatch — the whole commit path reused, selection, filter sweep, and count
labels included — and `writeHash` rides the set-field commit flip-only behind
the field's changed flag, so an equal-value transaction writes nothing and
the WHATWG equal-value hash assignment closes the echo loop. `persist items
:= "leanrx-toggle-lab.items"` seals persistence onto the region row table
under one sealed literal key: mount hydrates through the existing append path
from one `storageGet` (a missing, empty, or wrong-arity value fails closed to
the empty region), one `storageSet` rides the region-touch sweep per
region-touching transaction — the ADR-0050/0051/0058 shared touched flag —
and a filter change alone touches nothing and therefore persists nothing.
Serialization lives in generated code as a throw-free split/join escape; the
host moves strings only.
The ADR-0084 per-event drain wake is the last thing this component's row
vocabulary is here to witness. Five row events write four different field
sets, and the sweeps over `items` read three of them: the two `done`
predicate counts, the two `done` predicate selections and the filter table
can only move when `toggle` runs; the editing hint —
`hidden={count items (mode == "edit") == 0}`, an ordinary ADR-0059
predicate-count selection whose subject happens to be `mode` — can only
move when `edit`, `commit` or `keys` runs; the row total and the three
emptiness subjects can move on no drain at all; and the persistence
write-back reads every field, so nothing narrows it. Inside
`$lrx_region_0_dispatch` — the one function that knows which row event
ran, because `listenDelegatedCells` hands it the action — those become two
`region_drain_0_{c}` constants beside the ADR-0082/0083 pair, and a
`retype` keystroke lands in neither class: it drains its one retained row,
re-serializes the table, and re-evaluates nothing else at all. Every other
transaction function keeps the region-wide flags, because none of them can
queue a position at all. Still no host change and no runtime ABI bump.

The ADR-0085 serialization cache is what ADR-0084 left standing. The
write-back reads every field, so no wake rule narrows it, and this lab's
survey priced a 10 000-row keystroke commit at 93.5% serialization against
0.9% key scan. `items` rows therefore carry one cell behind `(label, draft,
done, mode)` — slot 5 — holding that row's serialization, `null` until it is
encoded; the write-back encodes only the `null`s and reads the rest back.
Because the cell rides the row tuple it is keyed on row identity, so this
lab witnesses the whole invalidation matrix on three rows through the
`storage:items:encode:{n}` trace: an append encodes one row, a `toggle`, an
`edit`, each `retype` keystroke and the Enter commit encode one each, a
filter change encodes nothing because it touches nothing, the ✕ removal and
`clearCompleted` encode **zero** — the kept-filter rebuilds the row array
around the same tuples, so the survivors' cells are still valid — while
`completeAll` and the `toggleAll` payload broadcast encode every row, and a
hydration encodes the whole table, which is exactly what normalizes a
hand-edited stored value. The stored string is byte-identical to what the
uncached sweep wrote, no region record slot moved, and once more: no host
change and no runtime ABI bump.

The ADR-0087 visibility contract is the last thing this lab witnesses about
persistence, and it is a contract rather than a change: the `storageSet`
rides the commit sweep, so the store is current the moment the dispatch that
opened the transaction returns. Three synchronous `Add item` clicks are three
dispatches inside one task — the shape a per-task flush would have collapsed
into a single `join` and a single `storageSet` — and a `localStorage` read
taken between them already sees what the commit that just returned wrote:
one row, then two, then three, with three `storage:items:write` entries
beside three `transaction:commit`. A filter click in that same task adds a
commit and no write, because the flush rides the region touch and not the
task, and the hash echo landing in a later task adds neither. What the
contract buys is what a deferred flush would have taken away: a tab closed at
any point loses nothing a returned dispatch wrote, so a remount hydrates
every row the burst persisted and no component that persists a region owes an
unload hook. Nothing in the emission changed — the round measured a per-task
flush at 1.00× on the only workload a user can drive, and a joined-string
cache on the region record at 1.52× against seven invalidation sites and two
record slots, and declined both. Once more: no host change and no runtime ABI
bump.

The ADR-0104 ownership declaration is the one attribute nothing here writes.
Four elements of this lab have a `value` or `checked` the program owns — the
row checkbox's `checked={done == "true"}`, the branch editor's
`value={draft}`, the controlled `#new-todo` input, and the `#toggle-all` box
whose `checked` follows a region count — and the compiler gives each of them
one static `autocomplete="off"`, because a control the program rewrites from
its state cell at every mount and every sweep has nothing the browser's
session-history entry is worth saving. Measured, saving it is worse than
useless: a back/forward traversal that re-creates the document restores the
user's edit *over* the value the mount just wrote, leaving the DOM
disagreeing with the cell — the ADR-0060 divergence class, arriving through
the one door left open. The cost the browser was charging for that was the
largest term of a flip's commit: the ADR-0063 route write at ten thousand
rows is 19.90 ms without the attribute and 3.53 with it, so the hide commit
is 3.39× and the whole round trip 1.64×. It changes nothing else — the
mount, the render and the detach are all inside their own A/A bands — and it
is one static attribute, so no host change and no runtime ABI bump. -/

namespace LeanRxExamples.ToggleLab

open LeanRx

abbrev ToggleSchema : Schema :=
  .field "added" Int <| .field "filter" String <| .field "draft" String .empty

def added : Field ToggleSchema Int := .here
def filter : Field ToggleSchema String := .there .here
def draft : Field ToggleSchema String := .there (.there .here)

open scoped LeanRxDsl

component ToggleLab (schema := ToggleSchema) where {
  state added : Int := 0;
  state filter : String := "all";
  state draft : String := "";
  event addItem := append items (s!"Item {added}", s!"Item {added}", "false", "view")
    then set added (added + 1);
  event addTodo := if trim draft == "" then skip
    else (append items (trim draft, trim draft, "false", "view"), set draft "");
  event completeAll := update items (set done "true");
  event clearCompleted := remove items (done == "true");
  event showAll := set filter "all";
  event showActive := set filter "active";
  event showCompleted := set filter "completed";
  event setDraft (value : String) := set draft value;
  event toggleAll (checked : Bool) := update items (set done checked);
  event confirmAdd (pressed : String) :=
    when "Enter" (if trim draft == "" then skip
      else (append items (trim draft, trim draft, "false", "view"), set draft ""))
    then when "Escape" (set draft "");
  filter items by filter := when "active" (done == "false")
    then when "completed" (done == "true");
  route filter := when "#/" "all" then when "#/active" "active"
    then when "#/completed" "completed";
  persist items := "leanrx-toggle-lab.items";
  row items toggle (checked : String) := set done checked;
  row items edit := set mode "edit";
  row items retype (value : String) := set draft value;
  row items commit := if trim draft == "" then remove
    else (set label (trim draft), set draft (trim draft), set mode "view");
  row items keys (pressed : String) :=
    when "Enter" (if trim draft == "" then remove
      else (set label (trim draft), set draft (trim draft), set mode "view"))
    then when "Escape" (set draft label, set mode "view");
  region items (label, draft, done, mode) := jsx%
    <li class={if done == "true" then "item-row done" else "item-row"}> [
      <span class="item-toggle"> [
        <input type="checkbox" ariaLabel="Toggle item" checked={done == "true"}
          onChange={toggle}/>
      ],
      {if mode == "view"
        then <span class="item-label" onDblClick={edit}> [{label}]
        else <input ariaLabel="Item editor" value={draft} onInput={retype}
          onKeyDown={keys} onDblClick={edit} autoFocus/>},
      <span class="item-commit"> [
        <button type="button" ariaLabel="Commit item" onClick={commit}> ["OK"]
      ],
      <span class="item-actions"> [
        <button type="button" ariaLabel="Remove item" onClick={remove}> ["✕"]
      ]
    ];
  view := jsx% <main class="toggle-lab"> [
    <h1> ["Toggle Lab"],
    <input id="new-todo" ariaLabel="New todo" value={rx% draft} onInput={setDraft}
      onKeyDown={confirmAdd}/>,
    <button type="button" onClick={addTodo} disabled={trim draft == ""}> ["Add todo"],
    <button type="button" onClick={addItem}> ["Add item"],
    <button type="button" onClick={completeAll}> ["Complete all"],
    <button type="button" onClick={clearCompleted}
      hidden={count items (done == "true") == 0}> ["Clear completed"],
    <p id="toggle-text"> [{"itemText": rx% s!"Items added: {added}"}],
    <ul id="items" ariaLabel="Items" hidden={count items == 0}> [<region items/>],
    <input id="toggle-all" type="checkbox" ariaLabel="Toggle all"
      checked={count items (done == "false") == 0} hidden={count items == 0}
      onCheckedChange={toggleAll}/>,
    <footer id="footer" hidden={count items == 0}> [
      <p id="items-left"> [
        <strong> [{count items (done == "false")}],
        {if count items (done == "false") == 1 then " item left" else " items left"},
        " of ", {count items}
      ],
      <button type="button" onClick={showAll}> ["Show all"],
      <button type="button" onClick={showActive}> ["Show active"],
      <button type="button" onClick={showCompleted}> ["Show completed"]
    ],
    <p id="edit-hint" hidden={count items (mode == "edit") == 0}> [
      "Editing: Enter saves, Escape reverts"
    ]
  ];
}

end LeanRxExamples.ToggleLab
