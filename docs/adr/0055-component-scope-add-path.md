# ADR-0055: Component-scope add path — RxExpr trim and the sealed skip-if event guard

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0054 closed TodoMVC's editor trim contract in row scope and recorded
its first open question explicitly: "`trim` lives in `RowExpr` only; the
component-state expression language (`RxExpr`) has no trim, so a
component-scope add path cannot normalize its draft. Whether TodoMVC's
top-level new-todo input needs an `RxExpr` trim (or arrives as a keyed
region append through row vocabulary) is the next parity decision."

TodoMVC's new-todo input is component state, not row state: the draft
lives above the keyed region, is mirrored into a controlled input
(ADR-0038), and its add contract is "a whitespace-only draft's add is
ignored — no todo appears and nothing else changes — while a valid draft
appends one todo with the trimmed title and clears the input." The
`append` event step (ADR-0041) already evaluates `rx%` expressions over
component state at event time, so the trimmed label needs only the
expression vocabulary; but "the add is ignored" is not expressible by any
existing update step: every declared event runs its transaction, writes,
and traces unconditionally.

## Decision

Two vocabulary decisions, taken together because TodoMVC's add contract
needs exactly both and nothing more.

**1. `RxExpr` gains the sealed `trim` unary.** `UnaryPrim.stringTrim :
UnaryPrim String String` — ASCII whitespace stripped from both ends,
`String.trimAscii` natively — staged by `rx%` as `trim field` or
`trim (expr)` through `RxExpr.trimOp`, lowered through `ReactiveIR` and
the scalar backend to the same `asciiTrimPattern` replace the ADR-0054 row
lowering and the hand-written Todo backend emit (deliberately not the
Unicode-aware `String.prototype.trim`; the differential gate pins that a
NBSP survives on both sides). It rides the ordinary scalar evaluators, so
it composes wherever staged expressions already sit — event writes,
append values, derived values, text sinks. Rejected: a general string
vocabulary (`toLowerCase`, `replace`, `slice`) — the same open-frontier
fork every ADR since 0043 has declined, declined again at component
scope; parity needs one normalization.

**2. Component events gain the sealed skip-if guard.** `EventGuard Γ` on
`EventSpec` — `field : Field Γ String`, `trimmed : Bool` — written
`event add := if trim draft == "" then skip else (step, …)`. When the
subject (one `String` state field, raw or behind the one trim unary)
equals the empty literal, the whole event is a no-op: the generated
dispatch function returns before the transaction begins — no begin
bookkeeping, no event trace, no write, no append, no dispatch, no commit
sweep. A miss runs the else-steps as one ordinary transaction. The shape
is sealed closed: one field, optional trim, the empty literal only (no
other literal is representable — the guard stores no literal at all), and
the sealed `skip` as the only hit. The rejected alternatives:

1. **A general conditional event vocabulary — rejected.** `if cond then
   steps else steps` over arbitrary predicates would fork the update
   language into control flow — the fork every row-scope ADR since 0043
   has declined, declined here for component scope. TodoMVC's add needs
   exactly "empty-after-trim means do nothing"; the guard is that
   contract and nothing else, `LRX-ELAB-123` naming the sealed surface.
2. **Affordance-only enforcement — rejected.** Disabling the Add button
   through the ADR-0045 `disabled` selection compares a raw field against
   a literal, so a whitespace draft would keep the button live; and a
   UI affordance is not a dispatch-layer contract — the event itself must
   be a no-op wherever it is triggered from.
3. **Normalizing per keystroke — rejected.** Trimming inside the
   `setDraft` typed event would destroy in-progress text (interior
   spaces type through a trailing-space state) and diverge from TodoMVC,
   which keeps the raw draft and normalizes at commit.
4. **`skip` as an `Update` constructor — rejected.** A conditional update
   step would put control flow inside the transaction (begun, traced,
   committed around a no-op). The guard is an event-level dispatch
   decision, evaluated before the transaction exists, which is what makes
   the no-op total — trace included.

The guard subject must be a source (`LRX-TYPE-114`): it is read before
the transaction, where a derived value is not yet recomputed. The typed
`Field Γ String` makes a cross-typed or out-of-bounds subject
unrepresentable, and the guard read joins the event summary's read sets.
The backend emits the subject inline — `state[i]` or
`state[i].replace(asciiTrimPattern, "")` — as the first statement after
the context destructuring; guarded components stamp the `event-guards`
manifest feature. **No host change and no runtime ABI bump**: unguarded
components emit byte-identical dispatch functions (the skip check is
emitted only when a guard exists), and every other lab and the
js-framework-benchmark bundle are byte-identical under the performance
freeze.

One consequence in the proof environment: `RxExpr.eval` now references
`String.trimAscii`, whose core UTF-8 machinery is classical, so the axiom
manifests of `eval_congr_on_deps` and the `eval` equation lemmas carry
`Classical.choice` transitively. The statements and proofs are unchanged;
the environment audit reviews the exact new manifests.

## Open questions

1. **Enter-to-add stays a recorded gap.** Component scope has no key
   branching: `when` arms are row vocabulary (ADR-0052), and a
   component-scope `onKeyDown` typed event fires per keystroke with no
   equality vocabulary. Toggle Lab proves the add contract through the
   Add button click path; whether TodoMVC's Enter confirmation arrives as
   a component-scope key selection (the ADR-0052 shape lifted out of row
   scope) or another form is the next parity decision.
2. **The guard literal is the empty string by construction.** A non-empty
   sentinel equality (skip while a mode field says so) is unrepresentable;
   growing the guard into a literal-carrying shape is a separate
   vocabulary decision nothing in TodoMVC needs.
3. **Other component predicates stay raw.** The ADR-0045 attribute
   selections still compare raw fields; a trimmed `disabled` selection
   (graying the Add button on a whitespace draft) is a separate decision.

## Consequences and limitations

- TodoMVC's new-todo contract is now expressible at component scope:
  Toggle Lab mirrors `draft` into a controlled input (ADR-0038,
  per-keystroke `setDraft`), and `addTodo` guards on `trim draft == ""` —
  a whitespace-only Add changes nothing (the draft is not even reset; the
  guard hit writes nothing at all) while a valid draft appends
  `(trim draft, trim draft, "false", "view")` and resets the draft in the
  same transaction, the appended row entering the full ADR-0041..0054 row
  vocabulary.
- `trim` in `rx%` composes anywhere staged expressions sit and costs one
  `replace` per evaluation; the guard costs one comparison (plus one
  `replace` when trimmed) at dispatch time, before any bookkeeping.
- A guarded event still declares its writes: the else-steps are ordinary
  steps, validated exactly as before (source-only writes, region arity,
  acyclic dispatch).
- Row scope is untouched: no dispatcher, `reconcile6`, or row-vocabulary
  change; the key set stays sealed at Enter/Escape; row scope still
  cannot observe component state or `s!`; and the parent-disposer gap of
  the region hosts is unchanged.

## Confirmation

Confirmed by the add-path round as drafted: the unary and the guard ship
through the generic backend with no host change and no runtime ABI bump —
every file of every other lab and of the js-framework-benchmark bundle
(`main.mjs` and manifest included) is byte-identical to the HEAD baseline
under the performance freeze. Toggle Lab's browser gates pin the no-op
(a whitespace-only Add leaves the transaction counters and the trace list
exactly at their pre-click values, the region metrics untouched, the row
count and counts unchanged, and the draft unreset) and the miss (one row
mount with the trimmed label, the draft reset through the controlled
reflection, and the appended row's editor opening on the trimmed mirrored
draft). The differential gate pins the trim semantics against
`UnaryPrim.stringTrim.eval` (interior whitespace, whitespace-only, NBSP
preserved); the model gates pin the good guarded event with its summary
read and the `LRX-TYPE-114` derived-subject rejection; two compile-fail
fixtures pin the surface (a non-empty guard literal and a non-`skip`
guard hit under `LRX-ELAB-123`); and the artifact gate pins the emitted
early return, the trimmed append evaluators, the draft reset, the
`listenValue` registration, and the `event-guards` manifest feature
beside the unchanged import shape.
