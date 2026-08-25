# ADR-0049: Row delegation kinds for dblclick and checkbox toggles

- Status: Proposed (decision draft)
- Date: 2026-08-25

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

## Decision (draft)

Extend, in a future round, the closed delegated row kinds from three to
five — `dblclick` and `checkedChange` — and reject the alternatives:

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

Open questions for the implementing round: whether a dblclick-only edit
affordance clears the accessibility gates (TodoMVC pairs it with no
keyboard path; the sealed template may want to require a sibling `keydown`
or button binding), and whether the checkbox needs a row-scoped `checked`
reflection (the ADR-0047 `value={…}` shape, `checked={done == "true"}`) so
the toggle state survives the retained-row update sweep.

## Confirmation bar

This draft is confirmed (Status → Accepted) when a TodoMVC-parity round
ships both kinds through the generic backend with browser gates showing
dblclick edit entry and checkbox toggling on retained rows (and the
agreement rules enforced by compile-fail fixtures) without a host change;
it is revised instead if the accessibility bar forces a different edit
affordance or the checkbox state proves to need a `Bool` payload class
after all.
