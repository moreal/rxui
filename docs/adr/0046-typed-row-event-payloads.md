# ADR-0046: Typed row event payloads through structural delegation

- Status: Accepted
- Date: 2026-08-25

## Context

ADR-0041 sealed keyed-region rows behind a closed action vocabulary bound by
click delegation, and ADR-0043 added sealed row updates — but a row could not
receive user input: the TodoMVC gate list requires per-row editing, and the
`listenDelegatedCells` host adapter already delivers the target's `value` and
the event's `key` to every dispatch alongside the action and row key. The
missing piece was a sealed surface for consuming those payloads without
letting arbitrary values or component state into row scope.

## Decision

A `row` item may declare one `String` payload parameter —
`row roster rename (value : String) := set label value;` — which marks the
sealed `RowEventSpec` payload-taking and admits exactly one new constructor
into its right-hand-side row expressions: `RowExpr.payload`, the delegated
payload of the dispatching event. Row templates bind payload-taking events on
native `input` elements with `onInput={rename}` (the delegated `value`
payload) or `onKeyDown={record}` (the delegated `key` payload); click stays
payload-less. The generated module registers one `listenDelegatedCells`
listener per bound event kind on the region container — `click`, `input`,
and `keydown` each get their *own* per-cell action array, so a click inside
an input's cell can never resolve that cell's typed action. The shared
dispatch function lowers `RowExpr.payload` to the delegated `value` or
`eventKey` argument selected by the event's template binding kind, which is
why a payload-taking event must be bound exactly once (`LRX-VIEW-033`).

Sealing rules, all checked by `ComponentSpec.check` or the elaborator:

- payload references are valid only in the right-hand sides of the declaring
  typed row event — never in template text or a payload-less event
  (`LRX-VIEW-033`);
- `input`/`keydown` bindings require a native `input` element and a
  payload-taking event; click bindings require a payload-less event
  (`LRX-VIEW-027`/`LRX-VIEW-033`);
- each row cell binds at most one row event per delegated kind
  (`LRX-VIEW-027`), so one input can carry `onInput` and `onKeyDown`
  together;
- payloads are `String` only and the parameter cannot shadow a row field
  (`LRX-ELAB-117`); `key` itself stays a reserved surface keyword, so the
  keydown parameter needs another name.

## Consequences and limitations

- No new host export and no ABI change: `listenDelegatedCells` has passed
  `value`/`checked`/`key` since ABI 15 and the extra listeners reuse it
  verbatim. Regions without typed row events emit exactly the previous
  single click listener, so the Nest Lab stage-1/2 modules were the only
  dists allowed to change.
- A typed row dispatch is an ordinary ADR-0043 update: it resolves the row
  by key scan, writes the evaluated fields, and drains exactly one
  `updateAt` through the commit sweep; the update callback never touches the
  input element, so the typed value and caret survive the re-render.
- Row inputs are uncontrolled: reflecting a row field back into the input's
  `value` property is out of scope, as are `checked` payloads, `Bool`/`Int`
  payloads, payload-conditional actions, and key-filtered dispatch (an
  Enter-only commit needs a conditional vocabulary that does not exist in
  row scope). A structural reconcile that remounts a row recreates its input
  empty — acceptable while appends and removals are the only structural
  operations.

## Confirmation

Nest Lab's roster rows grew a third field and an edit input: Chromium gates
per-keystroke renaming through the delegated value payload (text, input
value, and update-only region instrumentation), keydown recording through
the key payload (Enter writes `key:Enter` and performs exactly one retained
update), payload composition (`"key:" ++ pressed`), field retention across
marking and removal, and the unchanged stage-1/2 behaviors.
