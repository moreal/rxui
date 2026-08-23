# ADR-0027: Validate monotone keys without an index in the keyed region

- Status: Accepted
- Date: 2026-08-23

## Context

ADR-0026 left the keyed region's key index as the one validation cost on the
js-framework-benchmark's create and append paths: `update` registered every
new key in a persistent `Map` before the first callback (the duplicate-key
contract, `LRX-REGION-001`) and unregistered it on disposal. A CDP sampling
profile of the create-10,000 handler puts that index work at about 0.8 ms of
the 2.2 ms script gap to the upstream vanilla implementation (paired,
interleaved page loads; the rest is the `Nat` → `BigInt` id representation,
the two per-row delegated-action attributes in the cloned template, and
garbage-collection volume). The index only ever answers two questions: is a
key that is not at its previous position already mounted, and does a key
repeat. The benchmark's lists are model rows in id order, so neither question
needs hashing: strictly increasing keys are pairwise distinct, and a list whose
previous rows all matched by position cannot retain a row elsewhere.

A consecutive comparison proves distinctness only where `<` is a strict total
order. It is one within numbers (NaN fails both directions), within bigints,
and within strings, but not across number and string keys (`"10" < "5"`,
`"5" < 6`, and `6 < "10"` all hold), so the fast path is restricted to keys of
one of those three types.

## Decision

`createKeyedRegion.update` keeps the validate-first rule and changes only how
it validates. Keys are still matched by position first. The first key away from
its position decides the rest of the pass:

- if the keys are all numbers, all bigints, or all strings and strictly
  increasing or strictly decreasing, they are distinct: a key is looked up
  only while some previous row is still unmatched (it may be a retained row
  away from its position);
- otherwise every key away from its position is looked up, and a repeated key
  drops the index and throws `LRX-REGION-001` before any callback or DOM
  mutation.

The index is built from the previous rows when an update first needs it
(every earlier key of that update was retained by position, so nothing else
is in flight), every new key registers in it while it exists, and it is
dropped whenever an update retains nothing (and on disposal), so a fill, an
append, and a replacement in key order never hash a key; `removeAt`
unregisters its key only while an index exists; `swapAt` and `updateAt` are
unchanged. The runtime ABI is unchanged: no export, callback, or error changes,
and older and newer hosts and artifacts interoperate.

## Consequences

Create-10,000 falls about 0.9 ms locally (paired medians, 12 clicks per page,
10 rounds), create-1,000 and replace-all about 0.1 ms each, and the other
operations are unchanged within noise. A region whose keys are not monotone, or
that retains rows away from their positions, builds the same index it had
before, at the first update that needs it instead of incrementally, and keeps
it from then on; its per-update cost is otherwise unchanged. The region host
grows by the monotone check and the lazy index builder, so the flattened
benchmark module and the size baseline move accordingly.

## Validation

The fake-DOM suite adds a deterministic fuzz over number, bigint, string,
mixed numeric-string/number, symbol, and object keys in ascending, descending,
random, and append-to-current shapes with repeated keys injected at arbitrary
positions (rejected before any callback or mutation, identity retained,
mount/update counts exact, `removeAt` interleaved), and a directed case that
includes the non-transitive mixed-type lists; a differential fuzz against the
previous host (not committed) compared callback order, DOM order, metrics, and
rejections over 32,000 random updates, swaps, removals, and single-row updates
with no difference. The js-framework-benchmark browser gate and the upstream
run record the results in `BENCHMARK.md`.
