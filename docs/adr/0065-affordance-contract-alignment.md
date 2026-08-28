# ADR-0065: Affordance-contract alignment — surveyed and rejected

- Status: Accepted
- Date: 2026-08-28

## Context

Since ADR-0055 every affordance round has recorded the same sentence —
"the affordance is not the contract" — and ADR-0059 OQ1 and ADR-0061
OQ1 carried its open half: whether affordance-contract *agreement*
should be checkable. This round decides that question on the
checkability axis. Toggle Lab holds every affordance-contract pair the
vocabulary can spell, so the survey is exhaustive over three pairs.

**Pair A — the hidden clear-completed button (ADR-0059) against the
predicate removal (ADR-0050).** The affordance sits in the view model as
`AttrSelect.hiddenIfEmpty "items" span (some (2, "true"))` — the
anonymous `Option (Nat × String)` pair ADR-0064 deliberately left
unjoined — and the contract sits in the event table as
`Update.regionRemoveIf "items" ⟨.field 2, "true"⟩`, the sealed
`FieldPredicate`. The two spellings differ but both derive
`DecidableEq`, and `FieldPredicate.ofField` normalizes the pair, so the
validator could compare them: `ComponentSpec.check` already holds
`split.attrSelects` and `split.events` with their element paths and
`Update.regionRemoveIfTargets` carries the whole predicate since
ADR-0064. The comparison is representable; the pair is checkable.

**Pair B — the checked toggle-all reflection (ADR-0060) against the
payload broadcast (ADR-0061).** The affordance is
`AttrSelect.checkedIfEmpty "items" span (some (2, "false"))`; the
contract is `BroadcastEventSpec` with assignments `[(2, .payload)]`.
Only the region name and the field index are comparable. The meaningful
half of the alignment — the box reads "all done" and toggling writes
`done` consistently with that reading — hinges on `"false"` being the
complement of `"true"` in the `done` field's value alphabet, and the
model does not carry that fact: row fields are uninterpreted strings,
and the payload is `RowExpr.payload`, a runtime boolean whose
`"true"`/`"false"` descent happens at the write. The checkable residue
(field membership) passes programs that never agree — a predicate
`(done, "yes")` mentions the broadcast field and reflects nothing. The
pair's alignment is unrepresentable where it matters.

**Pair C — the disabled Add button (ADR-0057) against the skip guard
(ADR-0055).** The affordance is
`AttrSelect.disabledSelect draft "" (trimmed := true)` — typed field,
stored literal, trimmed flag — and the contract is
`EventGuard ⟨draft, trimmed := true⟩`, whose literal is not even
stored: the empty string is the entire guard predicate language. The
comparison is exact and decidable. But the same guard is also the
contract of `confirmAdd`'s Enter arm, bound on the new-todo *input* —
one contract, two dispatch sites, at most one co-located affordance —
so any element-local rule is one-directional from the start.

**The pairing relation itself is not in the model.** No constructor
marks a selection as *the affordance of* an event; the only candidate
tie is element-path co-location, and Toggle Lab already defeats it in
both directions. The footer, the list wrapper, and the items-left line
carry `hidden` selections on elements with no binding at all — an
affordance with no co-located contract, which is the point of an
affordance. And the toggle-all input co-locates
`hidden={count items == 0}` (a predicate-free selection) with
`onCheckedChange={toggleAll}` (a broadcast with no predicate): a
co-location rule must first decide which selection kinds pair with
which event kinds, and that kind-compatibility table is exactly the
speculative vocabulary this series of ADRs declines to invent.

## Decision

**Reject the affordance-contract alignment check, as an error and as a
warning; the dispatch layer stays the one contract.** ADR-0059 OQ1 and
ADR-0061 OQ1 are closed by this rejection rather than carried. The
grounds, in order of force:

1. **Over-rejection is immediate on the checkable pairs.** The grammar
   deliberately admits an affordance whose predicate differs from its
   element's event: a button may hide on
   `count items (done == "false") == 0` while clicking
   `clearCompleted` (hide bulk-clear when nothing is left to do), or
   disable on a subject unrelated to its event's guard. These are
   presentation policies, legal today, exercised by no gate as defects;
   an equality error would reject them for disagreeing with a contract
   they never claimed.
2. **The strongest pair is unrepresentable.** Pair B's alignment lives
   in the value alphabet of an uninterpreted string field; checking the
   representable residue would certify nothing while suggesting it
   certifies agreement — worse than no check.
3. **The pairing relation would need new vocabulary.** An
   "affordance-of" edge in the model or a selection-kind ×
   event-kind compatibility table is surface-visible design either
   way, violating the round's own validator-only principle before the
   first comparison runs.
4. **A warning is new machinery protecting no contract.** Every one of
   the validator's diagnoses is a hard `ComponentError`; there is no
   severity channel, and threading one through `ComponentSpec.check`,
   the elaborator surfacing, and the gates would be infrastructure
   whose only client is a check rejected on grounds 1–3.
5. **Agreement already has a mechanism: shared spelling.** ADR-0057
   made the affordance *evaluate the same equality* the guard does —
   same trim unary, same `asciiTrimPattern` emission — so agreement
   holds by construction exactly where the developer writes the same
   predicate, and ADR-0064 joined the spellings at the builder. The
   residual freedom — writing different predicates — is the
   presentation-policy freedom of ground 1, not a defect class.

The contract side needs no reinforcement: the existing gates observe it
directly wherever the affordance would mask it — the synthetic click on
the disabled Add button still returns before any transaction
(ADR-0057), the structurally dispatched click on the hidden
clear-completed button is still a no-op removal (ADR-0059), and the
toggle-all parity gates pin both directions of the broadcast against
the reflection (ADR-0061).

## Open questions

1. **A future field-alphabet seal could revisit Pair B.** If row fields
   ever carry a declared value alphabet (a boolean-valued field kind),
   the toggle-all alignment becomes representable; that would be a
   model vocabulary decision with its own parity driver, not a checker
   bolted onto uninterpreted strings.
2. **The carried rejections stand.** The component payload
   single-position rule (ADR-0061 OQ2), attribute-position count labels
   and the two-threshold grammar (ADR-0062), negated or composed
   predicate subjects, and the elaborator's six longhand `idxOf?`
   sequences (ADR-0064 OQ1) remain as recorded.

## Consequences and limitations

- No code changes: no grammar, no model constructor, no validator rule,
  no error code, and no fixture — the decision's artifact is this ADR
  and the DOGFOOD record, and every generated byte is untouched by
  construction. The freeze holds with nothing re-run; regression watch
  only.
- "The affordance is not the contract" is now a decided invariant, not
  an open question: affordance predicates are presentation policy, free
  to differ from the dispatch layer, and the dispatch layer alone is
  checked. Future affordance rounds inherit the closed form and need
  not carry the question forward.
- The dispatcher, `reconcile6`, the row vocabulary, and the host ABI
  are untouched; the key set stays sealed at Enter/Escape; the guard
  literal stays `""`; the count-label literal stays one; row guards
  stay single-field remove-or-commit; row scope still has no `s!`;
  branch cells stay single-level two-branch with exact click/dblclick
  agreement; and the parent-disposer instrumentation gap is unchanged.

## Confirmation

The survey's claims were confirmed by inspection: the three pairs' model
spellings (`AttrSelect.hiddenIfEmpty`/`checkedIfEmpty` with the
anonymous pair, `disabledSelect` with the typed field and trimmed flag,
`FieldPredicate` in `regionRemoveIfTargets`, `EventGuard` without a
stored literal, `BroadcastEventSpec` with `RowExpr.payload`), the
element paths carried by `MountedAttrSelect` and `MountedEvent` that
would make co-location computable, the affordances without contracts
and the co-located non-pairs in Toggle Lab's own view, and the absence
of any warning channel among the validator's diagnoses. The decision
changes no code: the full gate suite is green unchanged (`check.sh`),
`git status` shows no generated `.mjs` or manifest change, and the
js-framework-benchmark size gate still passes against the checked-in
byte-identity baseline.
