# ADR-0060: Region-count checked reflection — the toggle-all display half

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0058/0059 sealed the region-count boolean as a visibility subject:
`hidden={count region == 0}` and its predicate form reflect one declared
region's row count against the zero literal into the `hidden` property,
riding the region-touch sweep beside the ADR-0050 count texts. TodoMVC's
remaining parity axis reads the same boolean the other way: the toggle-all
checkbox is *checked* exactly while every row is complete — that is, while
the count of not-done rows is zero. The subject already exists in the
vocabulary; only the exported property is missing.

The parity has two halves. The display half — the box's checked state
following the region — needs nothing but the ADR-0059 subject written into
`checked` instead of `hidden`. The action half — clicking the box toggling
every row on *and off* — needs a delegated checked payload to flow into a
component-scope region broadcast, and the ADR-0050 broadcast only carries
sealed row expressions; the payload is unrepresentable. This ADR closes
the display half and the check direction of the action (the payload-less
`completeAll`), and leaves the uncheck direction to a payload round.

## Decision

**Extend the sealed region-count selection with the one `checked` export
and nothing else.** `checked={count region == 0}` or
`checked={count region (field == "literal") == 0}` on a static
`type="checkbox"` input is the `AttrSelect.checkedIfEmpty` selection —
the ADR-0058 total-count or ADR-0059 predicate-count subject with the
written property flipped from `hidden` to `checked`. The input's `checked`
boolean property reflects whether no row of the named declared region
satisfies the predicate (or exists at all, in the total form).

The surface is claimed by the same component-command rewrite: the accepted
count-headed shapes resolve the region and the field against the declared
inventory and rewrite to the internal `regionChecked% "region"` /
`regionChecked% "region" fieldIndex "literal"` attribute. Only
count-headed `checked` values are claimed — every other dynamic `checked`
value keeps its existing meaning: the ADR-0038 controlled reflection at
component scope and the ADR-0049 row checked reflection in row templates.
A count-headed value in any other shape — a nonzero threshold, a bare
count, a predicate without the comparison — reports `LRX-ELAB-125`; an
unknown predicate field reports `LRX-ELAB-119`; an unknown region or
out-of-bounds predicate field at the model reports `LRX-VIEW-042`, the
codes the hidden selection wears.

Two static-scope rules are new, both under `LRX-VIEW-043`:

- **The checkbox origin rule.** The selection demands a static `input`
  element carrying `type="checkbox"` — the ADR-0049 rule ("the `checked`
  payload and property originate from checkbox inputs alone") read in
  static scope. A wrapper, a button, or a text input cannot carry it.
- **The payload-less toggle binding.** A static `change` binding may name
  a plain component event — the toggle-all box fires `completeAll` whole,
  discarding the delegated checked payload — but only from a
  `type="checkbox"` input. It mounts through the plain `listen` export a
  click binding uses: no form-event adapter, no value listener, no new
  host export. Every other change binding still resolves a typed value
  event (ADR-0038).

A `checkedIfEmpty` selection beside a controlled `checked` prop binding on
the same element would race two writers over one element property; the
selection counts as a reflected property for duplicate detection
(`LRX-VIEW-021`).

The lowering is byte-for-byte the hidden selection's with the property
name swapped:

- **Mount**: the box's ref joins the shared `attrRefs` and its cache slot
  mounts as the literal `true` through the existing `setProperty` export —
  an empty region has no row failing the predicate, so the box mounts
  vacuously checked, the same reasoning that mounts the hidden subjects
  true and the count texts at `"0"`.
- **Sweep**: whenever the region was touched this transaction (the shared
  `region_touched` flag), the commit sweep runs the ADR-0050 predicate
  scan (or reads the row-table length), compares the count against zero,
  compares the boolean against the shared attr cache slot, and writes the
  property only on a flip — the same tx[8]/tx[9] counters with
  `attr:{index}:checked` labels.
- **Filter independence**: a filter change alone never touches the
  region, so the scan does not even run; the box follows the row table,
  not the displayed rows.

The rejected alternatives:

1. **Other comparison operators and threshold literals — rejected.** The
   parity needs "no row still active"; the zero literal stays part of the
   sealed shape (`LRX-ELAB-125`), exactly as ADR-0059 sealed it for
   `hidden`.
2. **Negation and composition — rejected.** A checked-while-nonempty
   negation, a conjunction over predicates, or a subject over two regions
   forks the selection language into the open frontier every ADR since
   0043 has declined.
3. **State-field checked subjects — rejected.** `checked={someState}` at
   component scope already means the ADR-0038 controlled reflection; the
   region-count subject is the only aggregate `checked` form, and no new
   state-driven form joins it.
4. **A checked-specific host export — rejected.** The property write
   reuses the existing `setProperty` export; no host change and no
   runtime ABI bump.
5. **Widening the selection beyond the checkbox — rejected.** `hidden` is
   meaningful on any element; `checked` is not. The ADR-0049 origin rule
   carries into static scope as `LRX-VIEW-043`.
6. **A form-event adapter for the toggle binding — rejected.** The
   payload-less change binding discards the checked payload by
   construction, so it mounts through the plain `listen` export; adapting
   `listenChecked` at component scope would ship a payload no event can
   yet receive.

## Open questions

1. **The uncheck path is unexpressed.** Clicking the checked box fires
   the same `completeAll`; its equal-value broadcast leaves every row done
   and the box's cache still true while the DOM box shows the user's
   uncheck. Toggle-all phase 2 needs a delegated checked payload flowing
   into a component-scope broadcast —
   `event toggleAll (checked : String) := update items (set done checked)`
   — and the ADR-0050 broadcast only carries sealed row expressions today.
2. **The affordance stays a reflection.** Nothing ties the box's checked
   state to `completeAll`'s contract, the ADR-0059 open question carried
   over.
3. **Row-scope selections stay untouched.** The ADR-0044 row class
   selection and ADR-0049 row checked reflection still compare raw
   projected fields.

## Consequences and limitations

- TodoMVC's toggle-all display parity is expressible: Toggle Lab's
  toggle-all checkbox carries
  `checked={count items (done == "false") == 0}` with
  `onChange={completeAll}`, mounts checked (empty region — vacuous
  all-complete), unchecks on the first not-done append, checks under the
  `completeAll` broadcast, unchecks when a done row untoggles or a row
  appends, ignores filter changes (the region is untouched), and restores
  the vacuous truth when `clearCompleted` drains the region — an
  evaluate-only step, the equal-value compare swallowing the write.
- A checked selection costs one row-table scan per region-touching
  transaction — the ADR-0050 count-text cost — and only there; the
  boolean cache keeps every non-flip write-free.
- The uncheck gesture on the box is visually honored by the browser but
  semantically a no-op until phase 2; the gate pins the divergence
  (evaluate-only sweep, cache true, DOM false) as the recorded gap.
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
under the performance freeze; only Toggle Lab's module, manifest (gaining
the `region-checked` feature), and graph (source spans only — the
selection joins no graph node) change. Toggle Lab's browser gates pin the
box checked at mount, the first not-done append's one-evaluation
one-write uncheck, the `completeAll` re-check, the untoggle and append
unchecks, the ✕ removal re-check, the `clearCompleted` evaluate-only
vacuous truth (one evaluation, no write), the filter-change
non-evaluation with the box unchecked while every not-done row is
filter-hidden, the box's change firing `completeAll`, and the uncheck
divergence (evaluate-only, DOM keeps the user's uncheck). The model gates
pin the forged predicate and total selections' mounted positions,
`select:checked:r:0:x` / `select:checked:r` debug markers, boolean value
type, graph exclusion, unknown-region and out-of-bounds `LRX-VIEW-042`,
the non-checkbox rejection and non-checkbox change binding
(`LRX-VIEW-043`), and the controlled-beside-selection duplicate
(`LRX-VIEW-021`); the elaborator gate pins Toggle Lab's mounted quadruple
(the trimmed `disabled`, the predicate and total `hidden`, and the
`checked` at the box's path) with its payload-less change binding and the
guide's `CountedRosterMini` triple; compile-fail fixtures pin the sealed
surface (a checked predicate count against a nonzero threshold,
`LRX-ELAB-125`, an unknown predicate field, `LRX-ELAB-119`, and the
selection on a non-checkbox element, `LRX-VIEW-043`); and the artifact
gate pins the four-slot mount block, the region-touch sweep with the
checked scan behind the hidden subjects, the plain-`listen` change
mount, and the `region-checked` manifest feature beside the unchanged
import shape.
