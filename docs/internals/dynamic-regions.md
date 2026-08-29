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
remove-if guard hit — and emits `removeAt` for it: the dispatch queues the
position ADR-0092's key search already resolved and the commit sweep drains
the queue before the reconcile, so the host's `update` is not entered and no
retained row's update callback runs.

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
component-event predicate removal, a broadcast and the ADR-0063 hydration
still reconcile; the hydration deliberately, because its rows arrive as a whole
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
that consume them — `childAt(container, i)` addresses the container's *i*-th
child, and only after the drains do the row table and the host agree — so the
three values the narrow path needs are snapshotted beside the wake flags,
before the drains empty what they name. Both sweeps report the number of rows
they read, as `predicate:{region}:read:{n}` and `filter:{region}:read:{n}`.
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
