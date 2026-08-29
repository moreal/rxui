# Dynamic region contract

M8 adds local dynamic regions after the static scalar path is already stable.
Static scalar sinks remain direct node/property writes. Only a declared region
may reconcile shape; LeanRx does not introduce a root-wide or general Virtual DOM.

`Region.LogicalNode` is a pure reference value for native/differential tests. It
is not a browser representation and is never serialized into generated runtime
state. Optimized region models retain opaque mount tokens so tests can distinguish
logical equality from DOM identity.

Each pure reconciler accepts only the prior result returned by its own mount or
reconcile operation. Result constructors and next-token counters are private,
so callers cannot supply duplicate current entries or reuse a stale token.
Logical instances remain inspectable as observations, but they cannot be fed
back as forged reconciliation state. Compile-fail and multi-step native tests
lock this reachability boundary.

The first conditional model has two operations:

- a same-branch update retains its token and records at most one direct scalar
  update;
- a branch transition disposes the old token exactly once and mounts one new
  token.

Lean proves that the optimized conditional result has exactly the reference
logical node. Browser lowering and DOM identity/disposal remain in the TCB and
are covered by the deterministic local-host and Chromium gates.

The positional model retains mount tokens for the common prefix, performs direct
logical-node updates at those positions, creates only an appended suffix, and
disposes only a removed suffix. Lean proves that its optimized mounted projection
equals full target-list recomputation. Positional identity deliberately follows
index, not application keys; reorder-sensitive collections must use the later
keyed region.

The keyed model validates unique natural-number keys before reconciliation.
Retained keys preserve opaque tokens through reorder, scalar node changes update
in place, removed keys report exactly their owned tokens for disposal, and new
keys alone allocate fresh tokens. Lean proves that the optimized mounted
projection equals full target-list recomputation. Token retention and disposal
counts are now compared with the connected browser region host in TodoMVC.

`runtime/leanrx_region.mjs` (the keyed region and the shared anchor, detach,
placement, and rebuild helpers) and `runtime/leanrx_unkeyed_region.mjs` (the
conditional and positional regions, shipped only by artifacts that import them)
are separate local reconcilers, not schedulers. They receive explicit target
items and compiler-generated mount/update/dispose callbacks and never discover
dependencies, observe reactive reads, or rebuild outside their anchors.
Conditional replacement, positional suffix ownership, keyed identity/reorder,
duplicate-key fail-before-mutation, copied instrumentation, and idempotent
disposal run against a deterministic fake DOM before browser dogfood.

A region host never disturbs the array it is handed (ADR-0094). `update(items,
…)` takes the caller's table, `updateAt(…, row, …)` one of its rows, and
`swapAt(…, items, …)` a target order; the `splice`, the two-slot exchange and
the positional removal a host performs are all on its own entry array, and none
of the three hosts writes, reorders, resizes, re-keys or retains a caller's.
That matters beyond tidiness because ADR-0092's generated `$lrx_row_seek`
resolves a dispatching key by binary search over `regions[r][1]` itself, which
is exact only while the table stays strictly ascending in `row[0]`, and
ADR-0093's audit stops at the call. The contract is checked rather than
reviewed: `Test/js/region_contract.mjs` hands every host a frozen copy of each
caller array and re-verifies its length, its element identities, and every
row's key slot after each later call, and the whole region suite runs behind
that guard. Violations report `LRX-HOST-001` with the rule, the host, and the
method named. The handle surface is closed by the same guard, so a new host
export — the event that already moves `runtimeAbi` — must declare which of its
arguments are caller arrays before the gate is green. Rows themselves cross
unfrozen on purpose: a host forwards them to generated callbacks that own the
ADR-0085 and ADR-0086 cache slots, and only slot 0 is the order's business.

Keyed placement is minimal. After validating the whole target, updating
retained rows, mounting new rows, and disposing removed rows, the host trims
the unchanged prefix and suffix of the retained order and moves only the
retained nodes outside one longest order-preserving subsequence; new nodes are
inserted before their successor. Among equally long subsequences the host keeps
earlier target positions in place, so reversing two rows moves only the second
and an edit focused inside the first survives. A swap therefore costs two
placements, a rotation one, and appends, prepends, middle insertions, and
removals place only the new nodes. Retained keys are matched by position first,
so an unchanged order never hashes a key. The first key away from its position
decides how the rest are validated: when every key is a number, every key a
bigint, or every key a string and the keys are strictly increasing or strictly
decreasing, they are pairwise distinct (`<` totally orders each of those types;
it is not transitive across them, so mixed types never qualify), and the host
consults its key index only while some previous row is still unmatched;
otherwise every key away from its position is looked up and a repeated key
drops the index and fails. The index is built from the previous rows when an
update first needs it, every new key registers in it while it exists, and it
is dropped whenever nothing is retained, so fills, appends, and replacements in
key order never hash a key. If a target retains no row, the region rebuilds:
when it owns its whole parent (its first node through its marker, with no
foreign sibling), the old rows are removed with one bulk clear, the marker is
re-appended, and, while the parent is connected, is not the active element, and
is about to receive rows, the parent is detached for the bulk insertion and
restored at the same position; otherwise each node is detached individually.
Pure clears and updates with a retained row never detach the parent. The "placements/moves" counter counts
`insertBefore` calls in every case, and a deterministic fuzz over random keyed
targets checks order, identity, leak-freedom, and the placement bound.

Keyed callbacks receive the caller's context. `update(items, context)` forwards
`context` unchanged as a trailing argument to `mountItem(item, index,
context)`, `updateItem(handle, item, index, context)`, and
`disposeItem(handle, key, context)`, so a generated mount can thread its
mount-local context (metrics, templates, state) to every row without building
a per-commit payload array; the delta region's `update` and `apply` forward it
the same way. `updateAt(index, item, context)` re-runs the update callback for
one retained position whose key must be `item[0]` (LRX-REGION-003 otherwise,
before any callback); it changes no shape, order, or identity and is
equivalent to an update whose other items are unchanged, so a backend may use
it when it can show that only that row's payload changed. Since ABI 13 two
more targeted operations follow the same rule: `swapAt(first, second, items,
context)` exchanges the retained rows at `first < second` (checking
`items[second][0]` at `first` and `items[first][0]` at `second` first) with at
most two moves and re-runs the update callback for exactly those positions,
and `removeAt(index, key, context)` disposes and detaches the retained row at
`index` (whose key must be `key`) while the later rows shift one position
without an update callback; a backend uses them when it can show that the
exchange or removal changes no other row's payload (for `removeAt`, that no
row's payload depends on its position). `removeAt` unregisters the key only
while an index exists; validation always fails before any callback or DOM
mutation. Since ADR-0097 the component backend shows exactly that for a
sealed single-row removal — the `remove` row action and every ADR-0053
remove-if guard hit: the dispatch queues the
position ADR-0092's key search already resolved and the commit sweep drains
the queue before the reconcile, so the host's `update` is not entered and no
retained row's update callback runs.

ABI 19 makes that drain unbounded. `removeMany(drops, context)` takes a
strictly ascending array of `[position, key]` pairs against the order the call
starts in, validates every pair before any callback or DOM mutation
(`LRX-REGION-003`), disposes and detaches exactly those rows, and closes the
gaps with one native copy per surviving run — one write clears a parent the
region owns outright when the set is the whole table. That clear is one
*call* and not one saving: ADR-0103 measured it at 0.974× against the
`removeChild` loop it replaces on a Toggle Lab row, because the browser
charges `368 ns` per row plus `156 ns` per node inside it whichever way the
nodes leave the document. ADR-0100's win was never there — it was in not
entering the reconcile. Since ADR-0100 the
commit sweep drains the whole queue through it whatever the length, and the
ADR-0050 component-event predicate removal queues into the same slot instead
of raising the dirty bit: the one loop that keeps the survivors also records
each dropped row's position and decrements the ADR-0099 accumulator, so no
reconcile, no rescan, and the ADR-0051 sweep takes its narrow path and reads
zero rows. ADR-0100 emitted no threshold because it measured that none is
worth emitting: a one-row `removeMany` ties the `removeAt` loop it replaces,
a thousand-row one beats it 3.5×, and the reconcile is never more than 1.0×
better anywhere.

ABI 18 adds the mounting counterpart: `insertAt(index, item, context)` mounts
one row through `mountItem` and places it before the row that holds `index`
now, or before the anchor marker at `index === current.length`; the index must
be an integer in `[0, current.length]` (`LRX-REGION-003` otherwise) and, while
a key index exists, the key must be absent from it (`LRX-REGION-001`). Every
other row keeps its handle, node and rendering. Since ADR-0098 the component
backend lowers a component event's `append` through it: the append counts
itself in the region record's last slot instead of raising the dirty bit, and
the commit sweep mounts the last *n* rows of the table it ends with — a tail
push shifts nothing, so no position is stored and none can go stale. The drain forwards an ADR-0075 region's children inventory as `rowContext`,
and a tail insert pushes each row's children onto its end — where the
reconcile's own in-order mount loop would have put them; a mid-table caller
would owe that argument separately. A
broadcast and the ADR-0063 hydration still reconcile; the hydration
deliberately, because its rows arrive as a whole
table into an empty region, where the reconcile clears and refills an owned
parent detached.

ADR-0099 takes the last of the commit's full-table walks off the same two
signals. The region record's final slot holds one accumulator cell per
distinct field equality the region's ADR-0050 counts and ADR-0059/0060
selections read, and each cell is moved where a row moves — an append adds
the tail row's contribution, a removal subtracts the dropped row's ahead of
the `splice`, a row stage subtracts the old tuple's and adds the new one for
exactly the cells its own write set can reach. Everything that rebuilds the
table wholesale raises the dirty bit, and one rescan refills every cell from
the table; the rescan is guarded on that bit *alone* and never on a sweep's
wake flag, because the cells are region state rather than a sweep's cache,
and it assigns rather than adds, so a path that moved a cell and then fell
back to the bit is corrected rather than doubled. The ADR-0051 filter sweep
narrows the same way: it visits the ADR-0043 pending positions and the
ADR-0098 appended tail, or `[0, length)` when the bit rose or the filter's
own state field changed. Those positions are exactly as valid as the drains
that consume them — only after the drains do the row table and the host
agree — so the three values the narrow path needs are snapshotted beside the
wake flags, before the drains empty what they name. Both sweeps report the
number of rows they read, as `predicate:{region}:read:{n}` and
`filter:{region}:read:{n}`.

A deselected row is **detached**, not hidden (ADR-0102). ADR-0101 priced the
difference — the browser charges `21.2 + 4.25e-5 · k · R` ms to hide `k` rows
in runs of `R`, and a row that is not in the document is in no run at all —
and the round trip measures 11.99× at ten thousand rows with five thousand
deselected. What that costs is the identity of row-table position with
container-child position, which the sweep used to rely on through
`childAt(container, i)` and which `insertAt`'s anchor and `ownsWholeParent`'s
one-write clear rely on still. The identity is not abandoned; it is moved
into the host, which is the only place that can hold both halves of it. The
sweep now calls `setDisplayed(position, key, displayed)` on the region
handle, the record's filter slot holding the container element is gone with
the navigation that needed it, and every other entry point restores the
identity for itself: `insertAt` anchors on the first *displayed* row at or
after its position, `removeAt` and `removeMany` detach a row that is already
out as a no-op and lose the owned-parent bulk clear while any row is out, and
`update` puts the whole table back into the container before it reconciles
and takes the same survivors out again after — so `placeInOrder`, the
longest-increasing placement and the bulk clear all still read the container's
children as the row table, for the whole of the one call that needs to. A row
is displayed exactly when its node is in the container, so the host caches
nothing the DOM does not already say.

Two things follow that a reader should not have to discover. A row root's
`hidden` property is no longer written by anything, so a `hidden` selection
in row scope would have no conflict to resolve and still does not exist. And
a deselected row is unreachable: the delegated listener is on the container,
so nothing dispatches for a row the filter is not showing — which is what a
user could already do, and is now what a script can do too.

Both directions of the flip are floors, and ADR-0103 priced them so that the
next round does not have to. Detaching is `368 ns` per row plus `156 ns` per
node, and no bulk write reduces it — one owned-parent `textContent = ""` for a
whole filtered-out table is 0.974× on this repository's widest row and 1.111×
only on a row that is a single text node, which is 1.1% of that shape's round
trip. Re-showing is what mounting `k` fresh rows into the same places
costs to within an A/A band (0.975–1.016× over six cells): the host's restore
is the price of rendering the rows and carries nothing of its own. ADR-0103
fitted that framework-free at `1.045 µs · N + 14.83 µs · k`; on the module
that ships it is **`0.67 µs · N + 20.6 µs · k`** (ADR-0105), and what sets the
per-row term is the row template — 5.45 µs for a row of text against 18.16 µs
for Toggle Lab's — so it is the author's declaration and not a lowering.

ADR-0105 re-split the commit around it once the history write was small, and
found it has exactly two terms: the route write and this sweep. The reconcile,
the ADR-0063 write-back and all three drains measure **exactly zero** in both
directions at every cell, because a filter flip raises no dirty bit, queues no
removal, counts no append and stages no row update. The sweep fits
`0.15 ms + 3.03 µs · k` at ten thousand rows and the route write is flat, so
the sweep is the larger of the two past `k` ≈ 11% of `N`. Neither is what the
flip *costs*: style and layout is 65.5–84.7% of the round trip at every cell,
almost all of it the show direction.

A region that rendered a **window** of its selection is the one thing that
would move that, and this host already implements it — a window is
`setDisplayed` applied to more rows, and every entry point above is written
for a row that is in the table and not in the parent. ADR-0105 declines it on
the recurring cost rather than on any contract: the restore bracket a
reconcile pays is only 0.29 µs per row out with no style or layout at all
(9.645 → 12.580 ms of reconcile from zero to ten thousand rows out) and the
one-time gain is real (105 ms at ten thousand rows with five thousand
selected), but every row crossing the window edge afterwards costs 24.6–29.0 µs
— 65.0 µs when the window moves one row at a time — against a laid-out list
that scrolls without entering script at all.

One number about the commit around it, because it was the largest and it is
not this file's: the ADR-0063 history write a routed filter field triggers
costs per row *in the document when it runs*, which since ADR-0102 the sweep
itself changes. Reordering it against the sweep is a wash across the round
trip (0.984–1.013× at seven cells), because the hide and show directions swap
which document each pays for. What made it large was that the browser saved
every row's checkbox into the session-history entry; ADR-0104 emits one static
`autocomplete="off"` on every control whose `value` or `checked` the program
writes, and the write fell from `2.00 µs` per row displayed to
`0.34 µs · rows + 0.15 ms` — 5.6–5.9× on the real emission, and 3.39× on a
ten-thousand-row flip's whole hide commit. Nothing in this file changed: the
attribute is written once at mount, the region host never sees it, and a row
the filter has detached is not in the document the write is charged for.
The ADR-0063 write-back keeps walking every row, because two thirds of its
cost is the bytes of a payload that is the whole table by contract and the
only layout that would narrow it costs 7.2 µs per key.

TodoMVC begins from a private pure `Todo.State` and closed `Todo.Msg` update
algebra. Add/toggle/delete/filter/edit/clear operations are total and preserve
monotonic unique natural keys; empty titles are rejected on add and delete the
edited item on commit. The native logical renderer and checked keyed projection
form the M8 differential reference. Artifact generation serializes
`Todo.logical` itself, and Chromium extracts the same normalized main/title/input,
keyed-row, filter, remaining, and completion observation from the generated DOM.
This is a test-only oracle, not a shipped Virtual DOM. The browser backend must
consume the public model rather than moving Todo semantics into the region host.

The generated Todo representation is explicit and backend-owned:

- each stored item is `[id : BigInt, title : String, completed : Bool]`;
- component state is `[items, nextId, filter, editingId, draft, newTitle]`, with
  `-1n` as the checked backend's no-edit sentinel;
- keyed render payloads extend an item with `editing : Bool` and `draft : String`.

The separate manifest-only type vocabulary describes this as
`list<record<TodoItem>>` plus five scalar slots. Those constructors cannot enter
the graph/runtime equality vocabulary and do not create a general arbitrary-record lowering. The pure Todo
update/logical model, specialized extractor, JavaScript AST backend, region host,
DOM, and delegated event adapter remain distinguished at the TCB boundary.

Todo uses an explicitly named reference-propagation pass after each committed
action rather than claiming M5 actual-change pruning. Standard instrumentation
counts every evaluated state-slot write and every compiler-emitted text,
property, or attribute host call. Separate region counters record mounts,
updates, moves, and disposals.

M10 adds an opt-in structural-delta adapter beside full keyed reconciliation.
The pure `ListDelta` vocabulary is closed; `reset` carries an `Array` target as
specified by the architecture. A private-constructor planned batch exposes
either the exact checked candidate or a visible reset fallback, and reports a
reset whenever any accepted batch contains one.
The JavaScript host (`runtime/leanrx_delta_region.mjs`, which imports the
shared placement and rebuild helpers from `leanrx_region.mjs` and is shipped
only by artifacts that import it) validates a whole tagged batch before
mutation and retains local identity/disposal ownership; it still performs no
dependency discovery or reactive scheduling. Its focused copied counters distinguish mounts, retained
updates, placements/moves, disposals, resets, accepted deltas, and validation
units; standard transaction metrics retain their existing meanings. The default
remains full keyed recomputation. See
[ADR-0017](../adr/0017-structural-delta-remains-opt-in.md) and the
[10k-row measurements](../performance/m10-data-grid.md).
