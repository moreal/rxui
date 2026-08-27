# ADR-0056: Sealed component key branching — the new-todo Enter

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0055 closed TodoMVC's component-scope add contract through the Add
button click path and recorded its first open question explicitly:
"Enter-to-add stays a recorded gap. Component scope has no key branching:
`when` arms are row vocabulary (ADR-0052), and a component-scope `onKeyDown`
typed event fires per keystroke with no equality vocabulary."

TodoMVC confirms the new-todo input on Enter, and the confirmation must be
*the same* guarded add the button runs: a whitespace-only draft's Enter is a
whole-event no-op (no write, no append, no trace) and a valid draft appends
one row with the trimmed label and clears the input. The pieces exist on
both sides of the gap. In row scope, ADR-0052's `RowAction.keySelect`
branches the delegated `key` payload against sealed literals inside the
generated dispatch function. At component scope, the `listenKey` host
adapter (part of the form-events host since ABI 11) already forwards
`event.key` to a generated dispatch function — ADR-0037's typed `String`
events ride it — but the only component vocabulary behind it is the typed
assignment `set field param`: every keystroke writes, nothing compares.

## Decision

Adopt the **sealed key-branched component event** — the ADR-0052 key
selection lifted out of row scope — and reject the alternatives:

1. **A general key predicate or open key literal vocabulary — rejected.**
   Arbitrary `if pressed == "…"` conditionals (or arms over any string
   literal) would open the update language into control flow over an
   unbounded key alphabet — the fork every ADR since 0043 has declined, and
   ADR-0052 already declined for row scope. The key set stays sealed at
   `{"Enter", "Escape"}` — the two keys the TodoMVC contract branches on —
   even though this round proves only the Enter arm.
2. **A per-keystroke `lastKey` write plus a guarded follow-up — rejected.**
   The existing typed event could store the key (`set lastKey pressed`), but
   no event fires "after" it to compare, the ADR-0055 guard compares against
   the empty literal only, and a state slot per keystroke is exactly the
   per-event write traffic the selection avoids.
3. **New event kinds per key (`onEnterDown`) — rejected.** The binding kind
   vocabulary is compiler-owned and closed; minting one kind per literal
   multiplies listener registrations by the key set. Which keys select which
   steps is dispatch logic, not binding structure — ADR-0052's exact
   argument, unchanged by the scope.
4. **Key filtering in `listenKey` — rejected.** A host-side filter is a host
   change and a runtime ABI bump for a comparison the generated dispatch
   function can perform on the argument it already receives — and the
   performance freeze wants the runtime byte-identical.
5. **Key-branched event over the existing `listenKey` dispatch — adopted:**

   ```
   event confirmAdd (pressed : String) :=
     when "Enter" (if trim draft == "" then skip
       else (append items (trim draft, trim draft, "false", "view"),
         set draft ""));
   ```

   lowering to `KeyEventSpec` — name, declared discriminant, and a list of
   `KeyEventArm` (key literal, optional ADR-0055 `EventGuard`, ordinary
   `Update` steps). The declared parameter is the discriminant, named in the
   head and compared implicitly by each arm (the ADR-0051/0052 table shape);
   an arm body is exactly the ADR-0055 event-body language — the plain step
   tuple or one `if trim field == "" then skip else (…)` guarded sequence —
   so Enter *is* the Add button's contract by construction, not by parallel
   maintenance.

Sealing rules, checked by `ComponentSpec.check` with the surface pinned by
`LRX-ELAB-124`:

- key literals come from the sealed `{"Enter", "Escape"}` set, each at most
  once, and the arm table is nonempty (`LRX-TYPE-115`);
- each arm body carries the ordinary component event obligations through
  the same checks as a plain event: source-only writes (`LRX-TYPE-107`),
  source-only reads (`LRX-TYPE-108`), a source-only guard subject
  (`LRX-TYPE-114`), declared dispatch targets (`LRX-ELAB-106`), and the
  region append/broadcast/removal table rules (`LRX-TYPE-109..112`);
- the discriminant is not spellable inside an arm body (`LRX-ELAB-124`, the
  ADR-0052 rejection restated): the matched literal already fixes it, and
  the component update language has no payload vocabulary to receive it —
  which also means a parameter name that collides with a state field makes
  that field unspellable in the arms, so pick a fresh name;
- a key-branched event declares a `String` payload parameter
  (`LRX-ELAB-124`) and binds through `onKeyDown` exactly once on a native
  input, and through no other kind (`LRX-VIEW-041`): a key equality over a
  `value` or `checked` payload is meaningless, and an unbound arm table
  would be dead vocabulary;
- key event names share the component event namespace (`LRX-ELAB-102`) and
  join the surface inventory in declaration order after the typed events.

The backend emits, per arm, one ordinary guarded transaction function — the
ADR-0055 shell over the arm's steps, tracing `event:{name}:{key}` so the
arms stay distinguishable in the transaction trace — and one dispatch
function that `listenKey` calls with `(state, context, event.key)`: one
`pressed === "literal"` conditional per arm returning the matched arm's
call. A key outside the table returns before the context is even
destructured — no transaction shell at all, cheaper than row scope's
empty begin/commit (which is the price of the *shared* region dispatch
function; a component key event owns its dispatch function, so the shell is
simply never entered). A matched arm's guard hit returns before its
transaction begins exactly as ADR-0055 specified. Arm evaluators join the
`event:{index}:…` namespace after the plain events, so plain-event
emission is untouched. Components with a key-branched event stamp the
`event-key-branches` manifest feature (and `event-guards` counts arm guards
beside plain-event guards); the key event counts once in `eventCount`.
**No host change and no runtime ABI bump**: `listenKey`, the import shape,
and every dispatch function of a component without key events are
byte-identical, and every other lab and the js-framework-benchmark bundle
are byte-identical under the performance freeze.

## Open questions

1. **The Escape arm is sealed but unproven at component scope.** Toggle
   Lab's new-todo has no revert contract (TodoMVC's spec gives the new-todo
   Escape no semantics), so the component-scope Escape arm exists in the
   vocabulary with no lab exercising it; the row-scope Escape revert
   (ADR-0052) remains the only proven Escape.
2. **Enter still inserts nothing at the browser level to suppress.** The
   new-todo input sits outside any form, so Enter has no default to
   prevent; a form-wrapped variant would need the ADR-0021 submit adapter's
   `preventDefault`, which is a different binding, not a key arm.
3. **The trimmed `disabled` affordance stays open.** Graying the Add button
   on a whitespace draft (an ADR-0045 selection over a trimmed subject) is
   still a separate decision; the dispatch-layer no-op is the contract on
   both the click and the Enter path either way.

## Consequences and limitations

- TodoMVC's Enter-to-add is now expressible and proven: Toggle Lab binds
  `onKeyDown={confirmAdd}` beside the per-keystroke `setDraft` on the same
  controlled input, and the Enter arm carries the identical guarded add the
  Add button dispatches — whitespace-only Enter leaves counters, trace,
  region metrics, counts, and the draft untouched; valid Enter appends the
  trimmed label and resets the draft; any other key is a complete no-op.
- Every keydown on the bound input still dispatches through `listenKey`;
  a non-matching key costs one string comparison per arm and returns —
  strictly less than the row-scope non-match, which begins and commits an
  empty transaction.
- The key set stays sealed at two literals; growing it is a future ADR, not
  a template freedom. Arms select component event bodies only — there is no
  key-branched typed assignment (`when "Enter" (set draft pressed)` is
  unrepresentable: the discriminant is consumed by the selection).
- Row scope is untouched: no dispatcher, `reconcile6`, or row-vocabulary
  change; ADR-0052's row `keySelect`, its sealed key set, and the row-guard
  vocabulary are exactly as before. The guard literal stays the empty
  string; row guards stay single-field remove-or-commit; row scope still
  has no `s!`; branch cells stay single-level two-branch with exact
  click/dblclick agreement; and the parent-disposer gap of the region hosts
  is unchanged.

## Confirmation

Confirmed by the Enter round as drafted: the extension ships through the
generic backend with no host change and no runtime ABI bump — every file of
every other lab and of the js-framework-benchmark bundle (`main.mjs` and
manifest included) is byte-identical to the HEAD baseline under the
performance freeze. Toggle Lab's browser gates pin the three-way contract on
the new-todo input: a whitespace-only draft's Enter leaves the transaction
counters, the trace list, the region metrics, the counts, and the draft
exactly at their pre-key values (the same whole-event no-op the Add button's
guard hit produces); a valid draft's Enter appends one row mount with the
trimmed label, resets the controlled input, and matches the Add button path
observable-for-observable; and a non-matching key (`ArrowLeft`, `Shift`)
moves nothing while the editor vocabulary stays untouched. The model gates
pin the forged good key event (arm table kept, summary union with the guard
read) beside the `LRX-TYPE-115` sealed-set/duplicate/empty rejections and
the `LRX-VIEW-041` binding rejections; the elaborator gate pins Toggle Lab's
`confirmAdd` (one Enter arm, trimmed guard on state slot 2, four-field
append, draft reset) beside the unchanged `addTodo`; compile-fail fixtures
pin `LRX-ELAB-124` (a payload reference inside an arm and a mixed arm/step
table); and the artifact gate pins the emitted `listenKey` registration, the
`pressed === "Enter"` dispatch, the arm's early guard return, the
`event:confirmAdd:Enter` trace label, and the `event-key-branches` manifest
feature beside the unchanged import shape.
