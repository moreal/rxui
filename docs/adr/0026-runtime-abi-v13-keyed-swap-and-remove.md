# ADR-0026: Bump the internal runtime ABI for keyed-region swap and single-row removal

- Status: Accepted
- Date: 2026-08-23

## Context

After ADR-0020 the js-framework-benchmark lowers `select` through the keyed
region's `updateAt`, but swapping two rows and removing one row still commit
the whole row list: the region validates every key by position, re-runs the
update callback for every retained row, scans the previous order for
disposals, trims the unchanged prefix and suffix, and (for a swap) computes a
longest order-preserving subsequence to place two nodes. A paired local
measurement against the upstream vanilla implementation (interleaved page
loads, several measured clicks each) puts that per-commit pass at about 0.10
ms of 0.14 ms script for a swap and 0.11 ms of 0.20 ms for a removal of 1,000
rows, while the two DOM moves a swap needs are already minimal and cost the
same through `insertBefore` as through `Node.moveBefore`. The upstream runner
multiplies those script costs by its 4× (swap) and 2× (remove) CPU slowdown.
None of this involves the checked Lean models; the benchmark model and its
operations are unchanged.

The same measurements show that the remaining create/append gap to vanilla
(about 2.4 ms warm, 3 ms from a fresh page, per 10,000 rows) is not the keyed
validation pass as such: the key index costs about 0.5 ms for 10,000 BigInt
keys and is required by the duplicate-key contract, the entry objects cost
nothing measurable, and the rest is the `Nat` → `BigInt` id representation and
its string rendering, the per-row delegated-action attributes, and diffuse
bookkeeping below the harness's 0.4 ms resolution. That gap is left as is.

## Decision

The internal JavaScript runtime ABI becomes version 13 for every artifact.

The keyed region gains two targeted operations next to `updateAt`, with the
same validate-first rule:

- `swapAt(first, second, items, context)` requires `items` (the target order)
  to differ from the current order only by the exchange of positions `first <
  second`; it checks `items[second][0]` at `first` and `items[first][0]` at
  `second` before any callback or DOM mutation (`LRX-REGION-003` otherwise),
  moves the higher node before the lower one and, unless the two are adjacent,
  the lower node before the old successor of the higher one, swaps the two
  entries, counts the moves, and re-runs `updateItem` for exactly those two
  positions (counting two updates).
- `removeAt(index, key, context)` requires the retained row at `index` to carry
  `key` (`LRX-REGION-003` otherwise); it removes the entry from the current
  order, calls `disposeItem`, detaches the node, unregisters the key, and
  counts one disposal. The later rows keep their handles and nodes one position
  earlier and receive no update callback.

The js-framework-benchmark backend lowers `swaprows` through a `commitSwap`
helper that calls `swapAt` with the model's two swap positions and `remove`
through a `commitRemove` helper that calls `removeAt` with the found position
and parsed key; both record the standard commit metrics. These are equivalent
to full commits because no row's label or selection flag depends on its
position, a swap changes no row's payload, and a removed selected row leaves
no row selected while no other row was selected before. Every other operation
still commits the whole row list.

## Consequences

ABI-12 and ABI-13 artifacts/hosts must not be mixed. All manifests move to
version 13. `swapAt` and `removeAt` are targeted operations whose equivalence
to a full `update` is a backend-level obligation (as for `updateAt`), checked
by the browser contract tests; they are not structural deltas, and the
structural delta vocabulary remains opt-in (ADR-0017). The keyed region host
grows by the two methods, which the flattened benchmark module ships; the size
baseline moves accordingly.

## Validation

Fake-DOM tests lock `swapAt` success (order, identity, move count, exactly two
update callbacks with the forwarded context, the adjacent one-move case),
key-mismatch and out-of-range rejection before any callback, and post-disposal
no-ops, and `removeAt` success (order, identity, disposal callback and count,
no update callbacks), mismatch rejection, and post-disposal no-ops; the keyed
fuzz and placement checks are unchanged. The js-framework-benchmark browser
gate exercises swap and remove after select, update, and append, including
node identity across the swap and the selection surviving both. The upstream
benchmark run records the new durations in `BENCHMARK.md`.
