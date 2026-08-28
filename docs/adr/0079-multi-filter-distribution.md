# ADR-0079: Filters distribute per region, including two over one state field

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0078 closed with two open questions, both about the ADR-0051 filter
view. Every filtered component in the repository — TodoMVC, Toggle Lab,
Mix Lab — carried exactly one filter, so the whole feature had only ever
been exercised at region index 0: the repository-wide scan suffix was
`_0` and nothing else. The two ungated axes were (1) two regions each
carrying a filter, and (2) two of those filters driven by the *same*
state field, which would make one `changed[field]` bit wake two sweeps
inside one commit.

The survey read the emission before touching anything:

- **Sweep identifiers.** The filter sweep allocates `filter_scan_
  {regionIndex}` and `filter_row_{regionIndex}` inside the per-region
  loop, so `_1` and `_2` are already reachable — nothing had ever
  reached them.
- **Container slots.** The container slot is `5 + counts?2`, computed
  from *that* region's feature set, so two filtered regions of different
  widths necessarily read different slot numbers out of records of
  different widths.
- **Wake conditions.** Each sweep is guarded by
  `region_touched_{regionIndex} || changed[filterField]`. The touched
  flag is that region's own `const`; the changed bit is the filter
  field's own slot. Two filters over one field name the same bit and
  different flags; two filters over two fields name neither in common.
- **Order.** The commit sweep walks `spec.regions` in declaration order
  and each region's whole block — counts, visibility, reconcile, drain,
  filter, persistence — is emitted inside that one iteration, so sweep
  order is declaration order regardless of which region an event touched
  first, and regardless of *why* each sweep woke.
- **Validation.** `validateFilters` rejects a duplicate *region*, not a
  duplicate field: `spec.filters` is an array keyed by region, and two
  entries naming two regions have always passed.

All five are coherent, and unlike ADR-0078's persistence cap there was
no scaffolding limit hiding behind them. So this round gates the
combination instead of sealing anything — but it gates it in a lab of
its own rather than in Mix Lab, because Mix Lab's evidence *depends* on
`pins` staying unfiltered: crew's container and pins' child inventory
share slot number 7, and giving `pins` a filter would move the inventory
and erase that witness.

## Decision

**Add Twin Lab (`examples/TwinLab.lean`) as the consumer of the
per-region filter contract, and pin both axes in its derived-artifact
and browser gates. No code change; runtime ABI stays 17.**

Twin Lab is deliberately narrow — three keyed regions, no child
components, no persistence, no routing — so the generated module reads
as the filter contract alone:

- `left` carries a count cell, so its record is eight slots wide with
  the container at 7; `right` and `solo` carry none, so the same
  container rides slot 5 of a six-slot record.
- `left` and `right` are the twins: both filtered by `mode`, with
  *inverted* arm tables, so one `set mode "on"` hides complementary rows
  in the two regions — an outcome no shared table or hoisted temporary
  could produce.
- `solo` is the control: filtered by `tone`, so it wakes on a different
  changed bit and on its own touched flag alone.
- `stir` (`append solo (…) then set mode "on" then set added (…)`) mixes
  the two wake reasons in one transaction.

The artifact gate (`Test/js/twin_artifacts.mjs`) pins the three-record
literal verbatim, the three `filter_scan_{i}` walks with their own
container slot expressions (`regions[0][7]`, `regions[1][5]`,
`regions[2][5]`), the three inline arm tables (two reading `state[1]`,
one reading `state[2]`), and the three wake guards — plus the absence of
`count_next_1_*`, `count_next_2_*`, and a dispatch for the two regions
that bind no row event.

The browser spec (`Test/browser/twin.spec.mjs`) pins the behavior: a
`mode` flip evaluates `left` then `right` and never `solo`, in one
commit, with two evaluate ticks and no mount or disposal in any region;
a `tone` flip evaluates `solo` alone and leaves both twins' `hidden`
values and region metrics untouched; a bare append or removal in `left`
wakes `left`'s sweep alone even though its twin shares the filter field;
and `stir` produces exactly one commit whose trace has the append first
(event order) and then all three evaluations exactly once in region
declaration order — the touched region reconciling before its own sweep
while the twins never reconcile at all.

The complementary rejection gains a witness too: `FilterRegionTwice`
pins that two filters over *one* region stay `LRX-TYPE-113`.

## Consequences

- The filter view is now a per-region feature in the same sense counts,
  visibility selections, and persistence are. The remaining constraint
  is one filter *table* per region, which is the same shape as
  ADR-0078's one persist writer per key: one region owns one container
  and one row table, so a second table would be two writers of one
  `hidden` property.
- The scan suffix `_2` is now reachable and gated. A codegen that ever
  hoisted the scan temporary, the container slot, or the arm table to a
  component-wide constant would fail the Twin Lab artifact gate loudly,
  because the three sweeps disagree on all three.
- Sweep order is now pinned as declaration order under *mixed* wake
  reasons, not just mixed event order (ADR-0078 pinned the latter). A
  sweep that ran touched regions before changed-field regions would fail
  the `stir` trace.
- Mix Lab keeps its asymmetry, and therefore its slot-7-means-two-things
  witness, because the new combination went to a new lab. That is the
  general rule this round establishes: a combination that would erase an
  existing gate's evidence gets its own lab.

## Open questions

1. **A filter over a region with pending row updates.** Twin Lab's
   regions declare no `row` update event, so the drain path
   (`updateAt`) never runs beside a filter sweep here; Toggle Lab and
   Mix Lab exercise the drain with a filter but only at region index 0.
   The `touched` flag already folds the pending array in, so the
   construction is uniform — unexercised at index > 0.
2. **A route over one of two filters.** `validateRoutes` caps the
   component at one route item and requires its field to carry a
   declared filter; with two filtered regions the field of a route is
   now ambiguous in a new way (`spec.filters.find?` by field would pick
   the first). No lab routes a shared filter field.
