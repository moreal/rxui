# ADR-0049: Row delegation kinds for dblclick and checkbox toggles

- Status: Accepted
- Date: 2026-08-25 (accepted 2026-08-26)

## Context

The closed delegated row event kinds are `click`, `input`, and `keydown`
(ADR-0041/0046): one structural `listenDelegatedCells` listener per region
container and kind, one static action array per kind, and the ADR-0047
cross-branch agreement rules defined per kind. The remaining TodoMVC
migration gaps need two interactions this vocabulary cannot express: edit
entry by double-clicking the row label (today Branch Lab substitutes an
Edit button, because row `click` requires a native button —
`LRX-VIEW-027` — and `dblclick` is rejected in row scope entirely), and
per-row completion toggles on a `type="checkbox"` input (the `change`
event's `checked` payload has component-scope vocabulary via
`AnyTypedEvent.bool` — ADR-0037 — but no row-scope counterpart). The host
side already carries both: `listenDelegatedCells` dispatches with
`target.checked === true` beside `value` and `key`, and `EventKind` already
names `dblclick` (payload class `none`) and `checkedChange` (payload class
`checked`, DOM event name `change`) for the static view.

## Decision

Extend the closed delegated row kinds from three to five — `dblclick` and
`checkedChange` — and reject the alternatives:

1. **Model both through existing kinds — rejected.** An Edit button is not
   TodoMVC's contract (the label itself is the affordance and the observable
   DOM has no button), and a checkbox driven by row `click` would read the
   toggle state from a payload-less event, resurrecting the read-the-DOM
   pattern the sealed vocabulary exists to exclude.
2. **An open per-event kind table — rejected.** Arbitrary event names would
   leak user text into the delegated listener registration and give the
   cross-branch agreement rules an unbounded case analysis; the kind
   vocabulary stays compiler-owned and closed.
3. **A `Bool` row payload class — rejected.** Row expressions are
   `String`-only by construction (ADR-0043) and typed row events take
   `String` payloads (ADR-0046); forking `RowExpr` into a typed expression
   language for one checkbox is not worth the surface.
4. **Two new kinds over the existing payload plumbing — adopted
   direction.** `dblclick` joins as a payload-less kind (`onDblClick={name}`
   binding a payload-less row event), permitted on non-button row elements
   so a label can carry it — the delegated dispatch is structural, so no
   `tabindex` or handler ever lands on the label element itself.
   `checkedChange` joins as a typed-kind binding (`onChange={name}`) on
   `type="checkbox"` inputs only, whose payload is the delegated `checked`
   boolean lowered to the strings `"true"`/`"false"` — the ADR-0045
   `aria-pressed` precedent — so a row event like
   `row todos toggle (done : String) := set done payload` keeps the sealed
   `String` update language unchanged.

Per-kind cross-branch agreement extends by origin class (ADR-0047):
`dblclick` bubbles from any content, so it takes `click`'s rule — both
branches must bind the same action, never one-sided. `checkedChange`
originates only from checkbox inputs, so it takes `input`'s rule — a
one-branch binding requires the other branch to contain no `input` element.
`keydown`'s focusable-tag rule is unchanged (`input`/`button` remain the
sealed template's only focusable tags). Both kinds ride the existing
`listenDelegatedCells` export and dispatch arguments, so the extension is
expected to need **no host change and no runtime ABI bump** — two more
listener registrations per bound region, two more static action arrays, and
the elaborator/validator/emitter kind tables.

The implementing round resolved the two open questions:

1. **No compiler-enforced keyboard sibling for dblclick.** The validator
   does not require a sibling `keydown` or button binding beside a
   `dblclick` edit affordance. Structural delegation never places a
   handler or `tabindex` on the label element, so the sealed template's
   accessibility posture equals TodoMVC's observable DOM (which pairs the
   dblclick with no keyboard path); the Toggle Lab axe gate passes on that
   DOM. The language guide instead advises keeping a keyboard-reachable
   path to the same action (a visible button, as Branch Lab retains, or a
   `keydown` binding) when the interaction must not be pointer-only — a
   template decision, not a kind-table rule.
2. **The row-scoped `checked` reflection ships with the kind.** A checkbox
   input may carry `checked={done == "true"}`, lowered to a sealed
   `RowReflectTarget.checkedIf` beside the ADR-0047 `value` reflection
   (checkbox inputs only and at most one per element — `LRX-VIEW-037`/
   `LRX-VIEW-035`) and written through the existing `setProperty` export.
   Without it the update sweep could not restore the toggle after other
   row-field updates and appended rows could not mount checked; with it
   the delegated `change` on the originating checkbox is an equal-value
   no-op, mirroring the ADR-0038 controlled-input finding.

## Confirmation

Confirmed by the toggle round: both kinds ship through the generic backend
with no host change and no ABI bump — the emitted import line is
byte-identical to Branch Lab's, `listenDelegatedCells` is untouched, and
the js-framework-benchmark bundle (module and manifest) is byte-identical
under the performance freeze. Toggle Lab's browser gates show label
dblclick entering the edit branch (focused via the ADR-0048 transfer, one
retained-row update, row identity preserved) and checkbox toggling driving
the `done` field through the `"true"`/`"false"` payload with the class
selection following; the cross-branch agreement lets the editor re-bind the
same `edit` action so an in-editor dblclick cannot clobber the draft.
`LRX-VIEW-037` (checkbox-origin rules) and the extended `LRX-VIEW-033`/
`LRX-VIEW-034` agreement rules are pinned by model gates and three
compile-fail fixtures. The `Bool` row payload class was not needed,
confirming the draft's rejection.
