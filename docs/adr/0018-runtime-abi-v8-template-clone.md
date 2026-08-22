# ADR-0018: Bump the internal runtime ABI for template cloning and keyed placement

- Status: Accepted
- Date: 2026-08-22

## Context

The js-framework-benchmark integration showed two runtime costs that are
unrelated to the checked Lean model: the keyed region placed nodes with a
last-to-first `nextSibling` walk, so swapping two rows moved almost every row
and paid a full-table layout, and every row was assembled from roughly 25
individual host calls although its static shape never changes.

## Decision

The internal JavaScript runtime ABI becomes version 8 for every artifact.

The DOM host adds `firstChild`, `nextSibling`, and `cloneTemplate`.
`cloneTemplate(build)` calls the generated static-template builder once per
builder function, retains the prototype subtree, and returns a deep clone on
every call. Generated mount code writes only the per-instance key, text, and
state-dependent attributes into the clone. The delegated click adapter resolves
`data-lrx-key` from the nearest keyed ancestor-or-self of the action node
inside the registered root, so one key on a row root serves every action link
in that row while existing action-node keys keep working.

The keyed region and the structural-delta region's full reconcile trim the
unchanged prefix and suffix, then move only the retained nodes outside one
longest order-preserving subsequence. A swap costs two placements, a rotation
one, and appends, prepends, insertions, and removals place only new nodes. When
a target removes every retained row and the region owns its whole parent
(first child through the region marker), the rows are removed with one bulk
`textContent` clear and the marker is re-appended. Validation still completes
before the first callback or DOM mutation, and the counters keep their
meanings: "placements/moves" counts `insertBefore` calls.

## Consequences

ABI-7 and ABI-8 artifacts/hosts must not be mixed. All manifests move to
version 8, including artifacts that do not clone templates. The keyed
placement counts recorded by deterministic browser gates decrease wherever a
reorder was previously paid as a chain of moves; those snapshots are updated
with the measured values. The DOM/region hosts, generated code, and browser
remain in the trusted computing base; the pure region theorems do not cover
the placement algorithm, which is checked by fake-DOM order/identity tests,
a deterministic fuzz over random keyed targets, and the Chromium gates.

## Validation

Fake-DOM tests lock swap, rotation, append, prepend, insertion, removal, and
bulk-clear placement counts, foreign-sibling ownership refusal, and
fail-before-mutation for duplicate keys. The js-framework-benchmark contract
spec, TodoMVC, Notes, Issue Browser, and Data Grid browser gates run against
the ABI-8 hosts, and the upstream benchmark run records the new swap, clear,
and creation durations in `BENCHMARK.md`.
