# ADR-0058: Empty-region visibility — hide-when-empty parity

- Status: Accepted
- Date: 2026-08-28

## Context

TodoMVC hides its `main` and `footer` sections while the todo list is
empty: the sections appear with the first todo and disappear with the
last. LeanRx could not express this. The ADR-0045/0057 attribute
selections compare one *state field* against a string literal, and the
region vocabulary observes rows only through the ADR-0050 count texts —
there was no way to drive an element's visibility from a region's row
table. The parity need is exactly one predicate: *is this region's row
table empty?* — the count texts' subject, read as a boolean.

The ADR-0051 filter view sharpens the requirement: a filter can hide
every row of a nonempty table, and TodoMVC keeps the sections visible in
that state (the footer still shows the counts and the filter links). So
the visibility subject must be the row table's total, never the number of
displayed rows.

## Decision

**Extend the attribute-selection vocabulary with the one sealed
region-subject form and nothing else.** `hidden={count region == 0}` on a
static view element is the `AttrSelect.hiddenIfEmpty region` selection:
the element's `hidden` boolean property reflects emptiness of the named
declared region's row table — its total row count compared against the
zero literal. The surface is claimed by the component command's rewrite
(the same pass that resolves `{count region}` children, ADR-0050), where
the region inventory exists; the accepted form rewrites to the internal
`regionHidden%` attribute and every other dynamic `hidden` value reports
`LRX-ELAB-125`. An unknown region reports `LRX-ELAB-119` at the surface
and `LRX-VIEW-042` at the model; the selection counts as its attribute
for `LRX-VIEW-001` duplicate detection; and unlike `aria-pressed` and
`disabled` it is valid on any static element — TodoMVC hides sections and
lists, not buttons.

The lowering is the ADR-0050 count-text shape carried into the ADR-0045
attr slots:

- **Mount**: the element's ref joins `attrRefs` and its cache slot mounts
  as the literal `true`, written through the existing `setProperty`
  export — regions mount empty by construction, the same reasoning that
  mounts count texts at `"0"`. The wrapper therefore starts hidden with
  no evaluation at all.
- **Sweep**: the selection reads no state field, so the state-driven attr
  sweep skips it and it joins no planned-graph sink (exactly like the
  count texts). Instead, whenever its region was touched this transaction
  — structurally dirty or holding pending row updates, the shared
  `region_touched` flag of ADR-0050/0051 — the commit sweep recomputes
  `items.length === 0`, compares it against the shared attr cache slot,
  and writes the property only on a flip, riding the tx[8]/tx[9] counters
  with the shared `attr:{index}:hidden` labels.
- **Filter independence**: a filter change alone never touches the
  region, so it does not even re-evaluate the selection; and because the
  subject is the row table, an ADR-0051 filter hiding every row leaves
  the wrapper revealed — visibility is structural emptiness, not filtered
  emptiness, by construction.

The rejected alternatives:

1. **Predicate count subjects — rejected.**
   `hidden={count items (done == "true") == 0}` would hide a section on a
   *slice* of the table; nothing in TodoMVC hides on a predicate, and
   admitting it opens the operator and literal questions below. The
   subject is the total, `LRX-ELAB-125` otherwise.
2. **Other comparison operators and threshold literals — rejected.**
   `!=`, `<`, `>`, and any nonzero literal read as a general
   numeric-predicate vocabulary (`hidden={count items < 2}` hides below a
   threshold). Emptiness is the one structural predicate the parity
   needs; the zero literal is part of the sealed shape.
3. **Negation and composition — rejected.** A `visible`-style negation or
   a conjunction over two regions would fork the selection language into
   the open frontier every ADR since 0043 has declined; the ADR-0057
   rejections carry over unchanged.
4. **General aggregate expressions — rejected.** `hidden={expr}` over
   arbitrary aggregates makes the re-evaluation set open-ended; the
   sealed subject keeps one region, one touched flag, one cache slot.
5. **A state-field `hidden` selection — rejected.** `hidden={field ==
   "literal"}` is representable through the existing vocabulary shape but
   answers no TodoMVC need; visibility parity is region-structural, and
   admitting both subjects doubles the surface without a use.
6. **A dedicated host export or wrapper element — rejected.** The `hidden`
   property write reuses the existing `setProperty` export on the
   existing wrapper element (in Toggle Lab the region's own `<ul>`
   container); no host change and no runtime ABI bump.

## Open questions

1. **Predicate-driven visibility stays out.** Hiding on a filtered or
   predicated count (e.g. a "clear completed" button that hides while no
   row is done) is a separate vocabulary decision; TodoMVC's own
   clear-completed affordance is a candidate but was not needed to close
   the hide-when-empty parity.
2. **The subject stays one region.** Visibility over several regions
   (conjunction) or over a region plus state is unrepresentable.
3. **Row-scope selections stay untouched.** The ADR-0044 row class
   selection and ADR-0049 checked reflection still compare raw projected
   fields; ADR-0057's state-scope trim extension and this region-subject
   extension leave row scope as it was.

## Consequences and limitations

- TodoMVC's hide-when-empty parity is expressible: Toggle Lab's items
  wrapper carries `hidden={count items == 0}`, mounts hidden, is revealed
  by the first append, re-hides when the ✕ removal, the guarded empty
  commit, or `clearCompleted` empties the table, and stays revealed while
  an ADR-0051 filter hides every row of a nonempty table.
- A hidden selection costs one `length` read and one equality per
  region-touching transaction; the boolean cache keeps every non-flip
  write-free (appending a second row evaluates once and writes nothing).
- `AttrSelect.fieldIndex`/`equals` became `fieldIndex?`/`equals?`: the
  region-subject selection has no state field and no compared string
  literal, and the accessors now say so instead of inventing values.
- The dispatcher, `reconcile6`, the row vocabulary, and the host ABI are
  untouched; the key set stays sealed at Enter/Escape; the guard literal
  stays `""`; row guards stay single-field remove-or-commit; row scope
  still has no `s!`; branch cells stay single-level two-branch with exact
  click/dblclick agreement; and the parent-disposer instrumentation gap
  is unchanged.

## Confirmation

Confirmed by the visibility round as drafted: the extension ships through
the generic backend with no host change and no runtime ABI bump — every
file of every other lab and of the js-framework-benchmark bundle
(`main.mjs` and manifest included) is byte-identical to the HEAD baseline
under the performance freeze; only Toggle Lab's module, manifest
(gaining the `region-visibility` feature), and graph (source spans only —
the selection joins no graph node) change. Toggle Lab's browser gates pin
the wrapper hidden at mount, revealed by the first append (with the
`attr:1:hidden` evaluate and write traces), re-hidden by the ✕ removal,
by `completeAll` + `clearCompleted`, and by the ADR-0053 guarded empty
commit, revealed-while-filtered with the all-hidden row list (property
and computed display observed directly — the boxless wrapper), the
filter-change non-evaluation, and the equal-value append no-op (one
evaluation, no write). The model gates pin the forged selection's mounted
position, debug marker, boolean value type, graph exclusion, unknown
region (`LRX-VIEW-042`), and duplicate (`LRX-VIEW-001`); the elaborator
gate pins Toggle Lab's mounted pair (the trimmed `disabled` beside the
`hidden` over `items` at the wrapper's path) and the guide's
`CountedRosterMini` wrapper; two compile-fail fixtures pin the sealed
surface (a predicate count subject and a nonzero threshold literal, both
`LRX-ELAB-125`); and the artifact gate pins the mount-time `true` write,
the region-touch sweep block with its labels and counters, the shared
attr slots, and the `region-visibility` manifest feature beside the
unchanged import shape.
