# ADR-0020: Bump the internal runtime ABI for keyed-region context forwarding and single-row updates

- Status: Accepted
- Date: 2026-08-22

## Context

After ABI 9 every js-framework-benchmark commit still allocated a projection
array per row (`[id, label, selected, context]`) so that the row callbacks
could reach the mount-local context and the selection flag, the keyed region
probed its key index twice for every key added to an empty region (a miss
followed by the insertion), and selecting a row re-ran the update callback for
all 1,000 rows although the render payload of exactly two rows changes; and
every artifact shipped the conditional and positional regions inside
`leanrx_region.mjs` although only TodoMVC imports them. None of these costs
involves the checked Lean models; the benchmark model, its operations, and the
`Row`/`State` lowering are unchanged.

## Decision

The internal JavaScript runtime ABI becomes version 10 for every artifact.

Both keyed regions forward a per-call context to their callbacks:
`update(items, context)` (and the delta region's `apply(deltas, context)`) pass
`context` unchanged as a trailing argument to `mountItem(item, index, context)`,
`updateItem(handle, item, index, context)`, and `disposeItem(handle, key,
context)`. Callers that pass no context keep their behavior; their callbacks
receive `undefined`. The keyed region gains `updateAt(index, item, context)`,
which re-runs the update callback for one retained position whose key must be
`item[0]` (`LRX-REGION-003` otherwise, before any callback); it changes no
shape, order, or identity and counts one update. When the keyed region is
empty, each new key is registered with one index insertion and a size that did
not grow reveals the repeated key, so validation still fails before any
callback or DOM mutation. `createConditionalRegion` and
`createPositionalRegion` move to `runtime/leanrx_unkeyed_region.mjs`, which
imports the shared anchor, detach, and snapshot helpers from
`leanrx_region.mjs`; artifacts that use neither no longer ship them.

The js-framework-benchmark backend commits the model rows themselves as the
keyed items, threads the model state through the mount-local context
(`[region, metrics, template, state]`), derives each row's selection flag in
the row callbacks from that context, and lowers `select` through a
`commitRows` helper that calls `updateAt` for the previously selected row (if
any) and the newly selected row. This is equivalent to a full commit because
`select` changes only the selected id and a row's selection flag depends on it
only through equality with the row's own id; every other row's label and flag
are unchanged. All other operations still commit the whole row list.

## Consequences

ABI-9 and ABI-10 artifacts/hosts must not be mixed. All manifests move to
version 10. Callback parameter lists grow by one trailing argument; Todo,
IssueBrowser, and Data Grid artifacts ignore it. The TodoMVC manifest adds
`./leanrx_unkeyed_region.mjs` to its host imports and its build copies the
module; `leanrx doctor` checks for it; the region gate syntax-checks and scans
it for banned mechanisms. `updateAt` is a targeted
scalar update of one retained row and not a structural delta; the structural
delta vocabulary remains opt-in (ADR-0017). The equivalence argument for the
benchmark's `select` lowering is a backend-level invariant (the region's
handles reflect the previous render payload of every row), checked by the
browser contract tests rather than by the pure region theorems, which still
cover neither the host placement algorithm nor single-row updates.

## Validation

Fake-DOM tests lock context forwarding through mount/update/dispose for both
keyed regions, `updateAt` success, key-mismatch, out-of-range, post-reorder,
and post-disposal behavior, and repeated-key rejection into an empty region
with a distant repetition, alongside the existing placement, bulk-clear,
rebuild, and fuzz checks. The js-framework-benchmark browser gate exercises
select followed by update, append, swap, and remove. The upstream benchmark
run records the new durations in `BENCHMARK.md`.
