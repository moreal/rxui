# ADR-0029: Represent js-framework-benchmark row ids as safe integers

- Status: Accepted
- Date: 2026-08-23

## Context

The runtime representation contract maps Lean `Nat` to a non-negative
JavaScript `BigInt` so that unbounded integer semantics survive the boundary,
and the js-framework-benchmark backend followed it for the model's row ids:
`nextId` started at `1n`, every generated row carried a `BigInt` id, each row
mount rendered it with `String(bigint)`, the keyed region's monotone-key check
compared bigints, and a delegated `select`/`remove` click parsed its key with
`BigInt(key)`. A paired CDP sampling profile of the create-10,000 handler
after ADR-0028 attributed a small, steady share of the remaining script to
that representation (the `BigInt` allocation per row in `buildData`, the
`BigInt` comparisons in the monotone check, and the `String(bigint)` rendering
per mount), and the paired click harness put it at about 0.25 ms per
create-10,000 click and 0.1 ms per replace-all once a forced garbage
collection before each measured click removed a bimodal major-collection
split that the round medians otherwise straddle (create-1,000 is unchanged).

The benchmark's ids are not unbounded in practice: they are allocated
sequentially from 1 and grow by at most the large row count (10,000) per
dispatched event, so reaching `Number.MAX_SAFE_INTEGER` would take about
9 × 10¹¹ events. Below that bound every operation the model performs on an
id (`+`, `==`) is exact in a JavaScript `Number`.

## Decision

The js-framework-benchmark backend represents the model's `Nat` row ids and
`nextId` as JavaScript safe integers (`Number`): the state's next id starts
at `1` and increments by `1`, generated rows carry `Number` ids, and the
delegated key (the id's decimal text) is parsed with `Number(key)` — a key
that is not a row id (`NaN`, `0`, …) matches no row and the event is ignored,
as an unknown `BigInt` key was before. The manifest discloses the
representation as the `safe-integer-ids` feature. The Lean model, the keyed
and DOM hosts, the runtime ABI, and the manifest's `stateSlots` (which name
the model's types) are unchanged; `BigInt` no longer reaches the module.

This is a decision about one hand-lowered backend whose id domain is bounded
by its own specification, not a change to the `RuntimeRep` contract: the
general component compiler still lowers `Nat` to `BigInt`.

## Consequences

Create-10,000 falls about 0.25 ms and replace-all about 0.1 ms locally
(paired medians, 16 clicks per page, 10 rounds, forced collection before each
measured click); a control comparison of two copies of the same build
resolves to 0.01 ms under the same protocol. The module shrinks by two bytes
(the size baseline moves 10,486 → 10,484 raw, 3,585 → 3,584 Brotli). A
delegated key that is not a decimal integer no longer throws from `BigInt()`
inside the click handler; it is ignored like any unknown id.

## Validation

The backend test checks that the state's next id is the Number `1`, the
delegated key is parsed with `Number`, no `BigInt` or bigint literal is
printed, and the manifest carries `safe-integer-ids`; the browser gate
exercises ids through creation, append, swap, selection, removal, and the
unknown-key precondition cases; the upstream run records the results in
`BENCHMARK.md`.
