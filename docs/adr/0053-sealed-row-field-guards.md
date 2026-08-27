# ADR-0053: Sealed row field guards for guarded remove stages

- Status: Accepted
- Date: 2026-08-27

## Context

TodoMVC destroys a todo when its edit commits empty: Enter (and the
blur-equivalent commit) on a cleared editor removes the row instead of
writing an empty label. The generic backend cannot say this. ADR-0043's row
stages are unconditional simultaneous assignments, ADR-0052's key arms
select *which* assignments run but recorded the gap explicitly in its first
open question: "Emptiness of a field is not expressible in row scope (no
guards), so an Enter-remove arm would fire on every Enter; TodoMVC's
destroy-on-empty-commit stays a recorded gap for whatever ADR introduces
row-field guards." Toggle Lab therefore committed empty drafts as empty
labels through both its OK button and its Enter arm.

Everything needed to evaluate such a guard is already in the dispatch
function's hands: the ADR-0043 scan resolves the dispatching row's current
field tuple before any write, and the removal sequence (kept-filter, dirty
flag, reconcile) has been emitted for the sealed `remove` action of every
region since ADR-0041.

## Decision

Adopt a **sealed remove-if guard on row stages** — one single-field string
equality, evaluated inside the generated dispatch function against the row
the existing key scan resolved, selecting between the sealed removal
sequence and the stage's assignments — and reject the alternatives:

1. **A general conditional vocabulary in row scope — rejected.** Arbitrary
   `if`/`else` over row expressions would open the sealed `String` update
   language into an expression language with control flow, the fork
   ADR-0049 declined for `Bool` and ADR-0052 declined again for payload
   conditionals. The guard ships as one closed shape instead: one field,
   one literal, equality only, `remove` as the only hit.
2. **Guard evaluation in the host adapter — rejected.** Teaching
   `listenDelegatedCells` or the region record to filter dispatches by
   field value is a host change and a runtime ABI bump for a comparison
   the dispatch function can perform on a row it already resolved — and
   the performance freeze wants the runtime byte-identical.
3. **A distinct guarded action constructor — rejected.** A separate
   `RowAction.guardedRemove` beside `update` (and a second arm form beside
   every ADR-0052 key arm) would duplicate the ADR-0043 assignment
   obligations across constructors that differ only in one optional field.
   The guard lives on the stage instead: `RowStage` carries the ADR-0043
   assignments plus an optional `RowGuard`, and `update` and `keySelect`
   arms share it — the plain action and every key arm gain the guard
   through one shape.
4. **Remove-if guards on row stages — adopted.** The surface is the
   if-then-else the row class selection already spelled (ADR-0044), at
   step position:

   ```
   row items commit := if draft == "" then remove else (set label draft, set mode "view");
   row items keys (pressed : String) :=
     when "Enter" (if draft == "" then remove else (set label draft, set mode "view"))
     then when "Escape" (set draft label, set mode "view");
   ```

   lowering to `RowStage.mk assignments (some (RowGuard.mk field literal))`.
   A guard hit removes the dispatching row through the same kept-filter,
   dirty flag, and reconcile the ✕ button's sealed `remove` runs — no
   field write, no `updateAt` queue entry, one row disposal with the
   retained survivors re-rendered by the dirty reconcile. A miss commits
   the else-steps byte-for-byte as an unguarded stage does.

Sealing rules, checked by `ComponentSpec.check` (`LRX-VIEW-040`) with the
surface pinned by `LRX-ELAB-122`:

- the guard is one row-field equality against one string literal — the
  field must be in bounds; no negation, no conjunction, no payload
  reference, no component state, and no trim normalization;
- the guard hit is the sealed `remove` and nothing else; assignments go in
  the else-steps, which carry the unchanged ADR-0043 obligations
  (nonempty, distinct in-bounds targets, in-bounds reads);
- a guarded stage stands alone: it mixes with no other steps in a `row`
  item, and inside a `when` arm it is the whole arm body;
- a guarded plain row event is payload-less (`LRX-VIEW-040`): guards
  select commit paths, and a payload-taking event fires per keystroke —
  the shapes meet only inside a `when` key arm, where the payload is the
  consumed discriminant (ADR-0052).

The dispatch function's guarded stage emits, after the existing
scan-resolve, one `row_item[field] === "literal"` constant with the removal
sequence under `if (row_guard)` and the unchanged
evaluate-assign-queue-trace sequence under `if (!row_guard)` — the
two-branch shape the update callback's branch cells already use. **No host
change and no runtime ABI bump**: the emitted import line,
`listenDelegatedCells`, the region record, and every listener registration
are untouched. The removal statements are the sealed `remove` action's,
extracted into one shared emitter helper; components without a guard emit
byte-identical modules and manifests (the js-framework-benchmark bundle is
byte-identical under the performance freeze); components with one stamp the
`row-guards` manifest feature.

## Open questions

Both resolved by the implementing round as drafted:

1. **No trim normalization.** TodoMVC trims the draft before the emptiness
   test; the sealed guard compares the raw field, so a whitespace-only
   draft commits as a whitespace label. Trimming is a row-expression
   vocabulary decision (a `trim` unary beside `append`), not a guard
   shape, and stays a recorded gap.
2. **Escape stays unguarded in the labs.** A guard is per-stage, not
   per-event: Toggle Lab guards both commit paths while its revert arm
   restores the label of an empty draft instead of destroying the row —
   the TodoMVC contract exactly.

## Consequences and limitations

- Destroy-on-empty-commit composes with the ADR-0046..0052 editor loop:
  the per-keystroke `retype` keeps `draft` current, Enter and OK guard on
  `draft == ""`, and the ADR-0051 filter view, ADR-0050 counts, and row
  identity of the survivors ride the same dirty reconcile the `remove`
  action always used.
- The guard is sealed at single-field `String` equality against one
  literal. Growing it — negation, conjunction, trim, non-`String`
  comparisons, guards selecting between two assignment stages rather than
  remove-or-commit — is a vocabulary decision for a future ADR, not a
  template freedom.
- A guarded stage costs its guard only when the event dispatches: the
  equality is one comparison after the row scan that already ran, and a
  guard hit replaces the update's write-and-drain with the removal's
  reconcile — no new sweep and no new transaction shape.
- Row scope still cannot observe component state, `s!` interpolation, or
  non-`String` equality; the key set stays sealed at Enter/Escape; and the
  parent-disposer gap of the region hosts is unchanged.

## Confirmation

Confirmed by the row-guard round as drafted: the guard ships through the
generic backend with no host change and no runtime ABI bump — Toggle Lab's
emitted import line is unchanged, and every file of every other lab and of
the js-framework-benchmark bundle (`main.mjs` and manifest included) is
byte-identical to the HEAD baseline under the performance freeze, which
also proves the removal-sequence extraction into the shared emitter helper
byte-identical. Toggle Lab's browser gates pin Enter on an empty draft
removing exactly the dispatching row (one disposal, one survivor update
from the dirty reconcile, no mount, no move, survivor DOM identity
preserved, counts following), the OK button agreeing through the guarded
commit with a nonempty draft still taking the ordinary commit path, and
Escape on an empty draft keeping the row — the unguarded revert arm.
`LRX-VIEW-040` is pinned by model gates (the good guarded update and
guarded key arm plus the out-of-bounds and payload-taking rejections) and
`LRX-ELAB-122` by four compile-fail fixtures (mixed steps, a guard in a
typed row event, a non-`remove` hit, an unknown guard field); the artifact
gate pins the guarded commit and Enter-arm sequences inside the dispatch
function beside the unchanged import lines and the `row-guards` manifest
feature. The rejected alternatives were not needed: no host-side guard, no
general row conditional, and no second action constructor.
