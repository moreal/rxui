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

`runtime/leanrx_region.mjs` is a separate local reconciler, not a scheduler. It
receives explicit target items and compiler-generated mount/update/dispose
callbacks. It never discovers dependencies, observes reactive reads, or rebuilds
outside its anchor. Conditional replacement, positional suffix ownership, keyed
identity/reorder, duplicate-key fail-before-mutation, copied instrumentation, and
idempotent disposal run against a deterministic fake DOM before browser dogfood.

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
The pure `ListDelta` vocabulary is closed, and a private-constructor planned
batch exposes either the exact checked candidate or a visible reset fallback.
The JavaScript host validates a whole tagged batch before mutation and retains
local identity/disposal ownership; it still performs no dependency discovery or
reactive scheduling. The default remains full keyed recomputation. See
[ADR-0017](../adr/0017-structural-delta-remains-opt-in.md) and the
[10k-row measurements](../performance/m10-data-grid.md).
