# ADR-0061: The payload broadcast — toggle-all phase 2

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0060 closed the display half of TodoMVC's toggle-all parity and the
check direction of its action: the box's `checked` follows the sealed
region-count boolean, and its payload-less change binding fires
`completeAll` whole. The uncheck direction stayed unrepresentable — the
ADR-0050 broadcast carries sealed row expressions only, so the delegated
checked payload had nowhere to go: clicking the checked box re-fired
`completeAll`, whose equal-value broadcast left every row done while the
DOM box showed the user's uncheck, a pinned cache-DOM divergence.

The missing sentence is exactly one: a typed component event whose payload
flows into a region broadcast. Both halves already exist — ADR-0038 typed
events carry a delegated `Bool` checked payload through the existing
`listenChecked` export, and ADR-0050 broadcasts write every row of a
declared region — only their composition is new.

## Decision

**Admit the payload identifier as a bare `set` right-hand side of the
ADR-0050 broadcast, inside a typed component event, and nothing else.**
`event toggleAll (checked : Bool) := update items (set done checked)` is
the payload broadcast: a typed component event whose single body step is
one region broadcast, where each assignment's right-hand side is either a
sealed payload-free row expression or the bare payload parameter.

The payload type and its descent are fixed: **the `Bool` checked payload,
lowered to the `"true"`/`"false"` strings at the broadcast write** — the
exact ADR-0049 downgrade the row-scope `checked` payload rides, emitted as
`checked ? "true" : "false"` inside the shared broadcast loop. The model
carries the event as the new `AnyTypedEvent.boolBroadcast` constructor
(name, parameter, region, assignments — no schema: like the plain
broadcast it reads no component state), so a `String` payload broadcast is
unrepresentable at the model and rejected at the surface
(`LRX-ELAB-126`). The view binds it through the ADR-0038 `onCheckedChange`
surface — the checked-change binding resolves it through the same payload
table a plain `Bool` typed event uses — and the backend mounts it through
the existing `listenChecked` form-event export: no new host export, no
runtime ABI bump. The dispatch function is the ordinary typed-event
transaction shell whose writes are the shared ADR-0050 broadcast body with
the payload expression in place of the inert string, so the region-touch
consequences are ADR-0050's verbatim: the dirty reconcile re-renders every
retained row with identity preserved, and the commit sweep updates the
count texts, the hidden selections, and the checked selection in the same
transaction.

The model validates the broadcast body under `LRX-TYPE-116` with exactly
the ADR-0050 obligations plus two payload rules: the region must be
declared, the assignments nonempty over distinct in-bounds targets with
in-bounds field reads; the payload stands alone (a composite right-hand
side containing the payload is rejected); and the payload must be written
at least once — a payload broadcast that never writes its payload is a
plain broadcast wearing a parameter.

The rejected alternatives:

1. **A `String` payload broadcast — rejected.** The checked binding
   delivers a boolean, and no parity needs keystrokes broadcast into rows.
   `LRX-ELAB-126` at the surface; the model constructor does not exist.
2. **Payload composition — rejected.** `trim checked`,
   `checked ++ "x"`, comparisons, and conditionals over the payload fork
   the row expression language for no contract; `LRX-ELAB-126` names the
   bare-payload rule. The sealed row expressions beside the payload keep
   their exact ADR-0050 vocabulary.
3. **The payload in other positions — rejected.** No `append` field, no
   `then set` state write, no guard subject, no second broadcast: the body
   is exactly one region broadcast. A typed event's body stays one of two
   sentences — `set field param` (ADR-0038) or
   `update region (set …)` (this ADR) — and the multi-step and any other
   single-step shapes keep their `LRX-ELAB-108` rejection.
4. **An `onChange={toggleAll}` component-scope spelling — rejected.** At
   component scope `onChange` is the `value`-payload change binding
   (ADR-0038) and, on a checkbox, the ADR-0060 payload-less toggle
   binding; overloading it a third way for `Bool` events would resolve a
   binding kind from the event table. The ADR-0038 `onCheckedChange`
   surface already says exactly this; Toggle Lab rebinds to it.
5. **Retiring the ADR-0060 payload-less change binding — rejected.** The
   rule stays: a checkbox's change binding may still name a plain
   component event and discard the payload (`LRX-VIEW-043` rules intact).
   Toggle Lab no longer uses it, but the vocabulary and its gates remain.
6. **A broadcast-specific host export — rejected.** `listenChecked`
   already delivers the payload and the broadcast body is generated code;
   no host change and no runtime ABI bump.

## Open questions

1. **The affordance still is not the contract.** Nothing ties the box's
   checked state to `toggleAll`'s broadcast beyond the developer writing
   both against the same predicate — the ADR-0059 open question carried
   over.
2. **The payload reaches one construct.** Guards, appends, key arms, and
   filter predicates still cannot observe a component-scope payload; each
   would be its own vocabulary decision.
3. **Row-scope selections stay untouched.** The ADR-0044 row class
   selection and ADR-0049 row checked reflection still compare raw
   projected fields.

## Consequences and limitations

- TodoMVC's toggle-all is complete: checking the box broadcasts
  `"true"` into every row's `done` (each row checkbox follows through its
  ADR-0049 reflection, the box re-checks through its ADR-0060 selection),
  unchecking broadcasts `"false"` the same way, and the sweep's
  evaluate-compare-write agrees with the browser's own uncheck — the
  ADR-0060 cache-DOM divergence gate is replaced by parity gates.
- An equal-payload broadcast re-renders the retained rows to equal values
  and leaves the sweep evaluate-only; an empty-region broadcast touches no
  row and writes nothing; a filter change alone still re-evaluates
  nothing (ADR-0051 non-touch preserved).
- The manifest gains the `payload-broadcasts` feature, and the
  broadcast-region inventory (`regionRowsMutate`, update-callback
  emission, `region-broadcasts`, `row-trim`) includes payload broadcasts.
- The dispatcher, `reconcile6`, the row vocabulary, and the host ABI are
  untouched; the key set stays sealed at Enter/Escape; the guard literal
  stays `""`; row guards stay single-field remove-or-commit; row scope
  still has no `s!`; branch cells stay single-level two-branch with exact
  click/dblclick agreement; and the parent-disposer instrumentation gap
  is unchanged.

## Confirmation

Confirmed by the toggle-all round as drafted: the extension ships through
the generic backend with no host change and no runtime ABI bump — every
file of every other lab and of the js-framework-benchmark bundle
(`main.mjs` and manifest included) is byte-identical to the HEAD baseline
under the performance freeze (full before/after builds into the
scratchpad); only Toggle Lab's module, manifest (gaining
`payload-broadcasts` and one event), and graph (source spans only)
change. Toggle Lab's browser gates pin the both-way parity (check → every
row done and box checked; uncheck → every row not-done, box unchecked,
divergence gone), the single-transaction joint update (one broadcast's
region touch re-renders both retained rows and updates the items-left
counts, the clear-completed hidden, the list hidden, and the toggle-all
checked together, with the exact evaluated/write trace deltas), the
equal-payload broadcast as an evaluate-only sweep, the empty-region
broadcast as a metric-preserving no-op, and the ADR-0051 filter-change
non-evaluation. The model gates pin the forged payload broadcast's body,
its empty summary, the checked-change binding resolution, the value
binding rejection (`LRX-VIEW-018`), and the `LRX-TYPE-116` family
(unknown region, empty and duplicate assignments, out-of-bounds target
and read, composed payload, never-written payload); the elaborator gate
pins Toggle Lab's typed inventory (`setDraft`, `toggleAll`), the
broadcast body, and the rebound checked-change binding at the box's path;
compile-fail fixtures pin the sealed surface (a `String` payload
broadcast and a composed payload, `LRX-ELAB-126`; an unknown broadcast
field, `LRX-ELAB-115`); and the artifact gate pins the `listenChecked`
import joining the form-event line, the `listenChecked` mount replacing
the ADR-0060 plain-`listen` mount, the generated broadcast body with the
`"true"`/`"false"` payload descent, and the `payload-broadcasts` manifest
feature beside the unchanged host-import shape.
