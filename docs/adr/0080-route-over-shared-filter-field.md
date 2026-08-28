# ADR-0080: A route seals onto the union of every filter table over its field

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0079 gated two filtered regions and a shared filter field, and closed
with two open questions. Both are about what happens *around* that shape
rather than inside it, and the survey read the emission before deciding
anything.

**The route question.** `validateRoutes` resolved the routed field's
filter table with `spec.filters.find? (·.field.index == route.field.index)`
— the *first* match. With one filtered region that is the only match; with
two, the sealed literal set (`default :: table`) silently became whichever
table was declared first. Two scratch components made the asymmetry
concrete: `filter left by mode := when "on" …` then `filter right by mode
:= when "off" …`, with a route arm naming `"off"`, was rejected

    error[LRX-TYPE-117]: route state literal off is outside the field's
    existing state literals (the declared default and the filter table)

while the same component with the arm naming `"on"` compiled — and both
diagnostics pointed at `left`'s span, the wrong table for the literal in
question. Swapping the two `filter` lines swaps which arm is legal. That
is a validation rule that reads declaration order, and nothing downstream
agrees with it:

- **Codegen never consults the filter table for a route.** The route arm
  functions write `state[field]` and nothing else; the dispatch chain
  tests the hash; the seed folds `readHash()` through the same table.
  All three are functions of the *route* table alone.
- **The emitted filter chains are already independent.** Each region emits
  its own `state[f] === lit ? … : … : false` chain from its own arms, and
  a literal a chain does not name falls through to `false` — that region
  shows every row. Two tables over one field never merge, and no literal
  is ever illegal at runtime.
- **Both sweeps wake on the same bit.** A `hashchange` dispatch is an
  ordinary set-field transaction, so `changed[field]` wakes
  `region_touched_{i} || changed[field]` for *every* region filtered on
  that field, in declaration order, inside the one commit.
- **`writeHash` rides the field, not a region.** The route write sits in
  `if (changed[route.field.index])`, emitted once per route item ahead of
  the sweeps — independent of how many regions filter on the field.

So the runtime already treats the routed field's literal space as the
union. Only the validator disagreed, and it disagreed in an
order-dependent way.

**The drain question.** A filter sweep had never run beside a pending-row
drain (`updateAt`) at region index > 0: Toggle Lab and Mix Lab pair them
only at index 0. `region_touched_{i}` folds that region's pending array
in, so the construction is uniform — but unwitnessed.

## Decision

**The sealed literal set of a route is the routed field's declared default
plus the union of the arms of *every* filter table over that field, and the
`LRX-TYPE-117` diagnostic names every one of those tables. Twin Lab gains
the route and a row update event to gate both axes.**

Rejecting a route over a shared filter field (the alternative) would have
been a cap with no counterpart anywhere in the emission: it would forbid a
combination the generated code handles correctly, and it would forbid it
only because *another* region — possibly one the route has nothing to do
with — happens to filter on the same field. The union is not a widening of
the contract so much as a correction: "the field's existing state
literals" was always the intended reading, and `find?` was a one-filter
shortcut that stopped meaning that when ADR-0079 made two filters legal.

Twin Lab is the witness for both axes, extended without disturbing the
three things its ADR-0079 gates rest on — `left`'s eight-slot record with
the container at 7 against `right`/`solo`'s six with the container at 5,
`left` and `right`'s inverted arm tables, and `solo`'s independent field:

- `filter right` gains a third arm, `when "mixed" (flag == "true")`. The
  `"on"`/`"off"` inversion against `left` is untouched; `"mixed"` is a
  literal the *second-declared* table alone names.
- `route mode := when "#/" "all" then when "#/on" "on" then when "#/off"
  "off" then when "#/mixed" "mixed"` routes the shared field. `#/mixed` is
  legal exactly because of the union; under the first-match rule it was
  rejected on `left`'s table. At runtime `"mixed"` filters `right` and
  leaves `left` showing every row — the fall-through the arm chain already
  encodes.
- `row right toggle (checked : String) := set flag checked`, with a
  reflected checkbox in `right`'s row, writes the very field `right`'s
  filter reads. One commit drains the retained row through `updateAt` at
  region index 1 and then re-selects it, both woken by the one
  `region_touched_1` flag; `left` stays asleep though it shares the filter
  field.

`RouteLiteralOutsideFilterUnion` is the complementary rejection: two
tables over one field, a route arm naming a literal in neither, still
`LRX-TYPE-117` — and the harness pins that the diagnostic now names *both*
filter declarations.

No host change; runtime ABI stays 17. The change is validation-only, so
every generated artifact outside Twin Lab is byte-identical.

## Consequences

- A route is now a view onto a *field*, not onto a region's table. The
  remaining route caps — one route item per component, a `String` field
  with at least one filter, a one-to-one `#/`-shaped table, exactly one
  arm on the declared default — are all properties of the route table
  itself, so none of them can turn on declaration order.
- The Twin Lab artifact gate pins that the union rule is a *validation*
  rule: `left`'s emitted chain must carry no `"mixed"` test, and there is
  still exactly one `route:mode:write` block for the two regions that
  share the field. A codegen that merged the tables, or wrote the hash per
  filtered region, would fail loudly.
- Twin Lab's browser gate now measures two commits per `mode` button
  click: the flip and the `hashchange` echo the canonical hash write
  provokes. The echo is an equal-value set-field commit that wakes no
  sweep, which the widened trace window asserts directly — one changed
  bit, two sweeps, one route write, across both commits. A hash-dispatched
  flip is a single commit, because the write it would make is equal-value
  and fires no further `hashchange`.
- The drain-beside-filter pairing is closed at index > 0: `updateAt` runs
  first and the sweep reads the settled row table, one update and no
  mount, move, or disposal, with row identity and the checked reflection
  preserved.

## Open questions

1. **A persisted region under a route.** Twin Lab has no persistence and
   Toggle Lab's route and persist item sit on one region; a *routed* field
   driving two regions of which only one persists has no witness. The
   write-back rides the region-touch sweep and the route write rides the
   field's changed flag, so the two are independent by construction.
2. **A row event on a region whose filter reads a field the row cannot
   write.** `right`'s toggle writes its own filter's subject; the
   complementary case — a row write that provably cannot change the
   selection — still runs the sweep, because the drain sets the touched
   flag. Whether that is worth narrowing is unexamined.
