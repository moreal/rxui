# ADR-0062: The count label — items-left singular/plural text

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0050 gave text positions the sealed row aggregates — the total and the
predicate row count, recomputed on the region-touch sweep and written
through the existing `setText` export — and every round since has read the
same counts as booleans (ADR-0058/0059/0060 against the zero literal).
TodoMVC's footer needs the last piece of its items-left grammar: the text
beside the number reads " item left" while exactly one row is active and
" items left" otherwise. The dogfood log has carried the singular/plural
flip as an unexpressed candidate since ADR-0050; nothing in the vocabulary
could select between two strings from a count.

The needed sentence is one comparison away from what exists: the ADR-0050
count subject — total or predicate — compared against a literal, choosing
one of two static strings. The one literal is English pluralization's
whole discriminant, the exact analogue of the zero literal the visibility
subjects sealed.

## Decision

**Admit a count-headed conditional text child comparing the ADR-0050 count
subject against the one literal and selecting between two static string
literals, and nothing else.**
`{if count region == 1 then "one" else "other"}` and
`{if count region (field == "literal") == 1 then "one" else "other"}` are
the count label: a text position whose content is one of the two strings,
following the named declared region's row count — total or the ADR-0050
single-field predicate count.

The surface is claimed by the same component-command rewrite that resolves
the `{count …}` children and the ADR-0058/0059/0060 attribute subjects: a
count-headed conditional in the two accepted shapes resolves the region
and the predicate field against the declared inventory and rewrites to the
internal `regionCountLabel%` child — the `regionCount%` shape carrying the
two branch strings. The comparison literal is sealed at one
(`LRX-ELAB-127` on any other threshold), the branches must be static
string literals (`LRX-ELAB-127` on any dynamic branch), an unknown region
or predicate field reports `LRX-ELAB-119`, and every non-count conditional
text keeps the unnamed-dynamic-text rejection (`LRX-VIEW-012`). At the
model the label is the optional string pair on `View.regionCount` and
`MountedRegionCount` — a label count joins the count inventory and carries
exactly the ADR-0050 obligations (`LRX-VIEW-038`: declared region,
in-bounds predicate field).

The lowering is ADR-0050's with the written value swapped:

- **Mount**: the position mounts as the `else` string — regions mount
  empty by construction, the empty region counts zero, and zero differs
  from one; the shared count cache slot mounts as the same string, so the
  cache and the DOM agree from the first paint (the `"0"` reasoning of
  ADR-0050 carried through the selection).
- **Sweep**: the label joins the region's count slots. Whenever the region
  was touched this transaction (the shared flag of ADR-0050/0051/0058),
  the commit sweep recomputes the count with the same per-slot scan every
  count position runs — **no scan sharing: ADR-0050 already re-scans per
  position, and the label re-scans identically; deduplicating equal scans
  across slots is an optimization no gate demands under the freeze** —
  selects the string against the one literal, compares it with the cache
  slot, and writes through the existing `setText` export only on a flip,
  riding the same tx[5]/tx[6] counters and `count:{region}:{slot}`
  labels.
- **Filter independence**: a filter change alone never touches the
  region, so the label does not even evaluate — the ADR-0051 non-touch
  carried to the label position.

The rejected alternatives:

1. **Threshold generalization — rejected.** Any literal other than one on
   either subject reads as a numeric-selection vocabulary; the parity
   needs "exactly one row", and the one literal stays part of the sealed
   shape (`LRX-ELAB-127`), the ADR-0058/0059 zero-literal reasoning.
2. **Negation and composition — rejected.** `!=`, conjunctions, multiple
   predicates, and multi-region subjects fork the selection language into
   the frontier every ADR since 0043 has declined; a negated or composed
   conditional falls through to `LRX-VIEW-012`.
3. **Non-count subjects — rejected.** A conditional text over state
   fields, row fields, or arbitrary aggregates makes the re-evaluation
   set open-ended; only count-headed conditionals are claimed, and every
   other conditional text stays unnamed dynamic text (`LRX-VIEW-012`).
4. **Dynamic strings — rejected.** State reads, concatenation, and any
   non-literal branch would give the text position a dependency set; the
   branches are two mount-time strings and the position's only input is
   the row table (`LRX-ELAB-127`).
5. **A separate sealed keyword surface — rejected.** A `plural%`-style
   form would add a keyword for what the conditional shape already says;
   the `if … then … else` spelling is the ADR-0044/0047 selection shape
   at a text position, claimed exactly like the count-headed attribute
   subjects.
6. **A label-specific host export — rejected.** The write reuses the
   existing `setText` export on the existing count path; no host change
   and no runtime ABI bump.

## Open questions

1. **The label reaches text positions only.** Attribute values, row
   templates, and prop positions cannot carry a count-driven string
   selection; each would be its own vocabulary decision.
2. **The subject stays one count against one.** Two-threshold grammars
   ("no items"/"1 item"/"N items") are unrepresentable — TodoMVC does not
   need them, and the zero case is the visibility subjects' territory
   (ADR-0058).
3. **Row-scope selections stay untouched.** The ADR-0044 row class
   selection and ADR-0049 row checked reflection still compare raw
   projected fields.

## Consequences and limitations

- TodoMVC's items-left grammar is expressible: Toggle Lab's line reads
  `<strong>N</strong>` plus the label plus the total, mounts plural on the
  empty region, flips to "1 item left" on the first append in one
  evaluation and one write, flips back on the second, and follows every
  toggle, ✕ removal, `clearCompleted`, and `toggleAll` payload broadcast
  with the number and the label updated in the same commit.
- A label count costs exactly a predicate count: one row-table scan per
  region-touching transaction, one cache compare, and a write only on a
  singular/plural flip — an equal-selection commit is evaluate-only.
- The manifest gains the `count-labels` feature beside `row-aggregates`.
- The dispatcher, `reconcile6`, the row vocabulary, and the host ABI are
  untouched; the key set stays sealed at Enter/Escape; the guard literal
  stays `""`; row guards stay single-field remove-or-commit; row scope
  still has no `s!`; branch cells stay single-level two-branch with exact
  click/dblclick agreement; and the parent-disposer instrumentation gap
  is unchanged.

## Confirmation

Confirmed by the items-left round as drafted: the extension ships through
the generic backend with no host change and no runtime ABI bump — every
file of every other lab and of the js-framework-benchmark bundle
(`main.mjs` and manifest included) is byte-identical to the HEAD baseline
under the performance freeze (full before/after builds into the
scratchpad); only Toggle Lab's module, manifest (gaining `count-labels`),
and graph (source spans only — the label joins no graph node) change.
Toggle Lab's browser gates pin the plural mount on the empty region, the
first append's singular flip as one `count:items:1:evaluated` and one
`dom:count:items:1:write`, the second append's plural return as another
single write, the equal-selection toggle as evaluate-only, the
filter-change non-evaluation, and the joint number-and-label agreement
across the toggle, the ✕ removal, `clearCompleted`, and both directions
of the `toggleAll` payload broadcast. The model gates pin the forged
label count's mounted position, retained label pair, and the ADR-0050
obligations with the label present (unknown region and out-of-bounds
predicate field, `LRX-VIEW-038`); the elaborator gate pins Toggle Lab's
three count positions with the label between the predicate count and the
total; the guide gate pins `CountedRosterMini`'s label position;
compile-fail fixtures pin the sealed surface (a non-one threshold and a
dynamic branch, `LRX-ELAB-127`); and the artifact gate pins the plural
mount text, the label's cache slot mounting as the else string, the
selection statement beside the untouched numeric slots, and the
`count-labels` manifest feature beside the unchanged host-import shape.
