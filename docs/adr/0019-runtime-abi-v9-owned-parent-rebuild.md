# ADR-0019: Bump the internal runtime ABI for owned-parent rebuilds and a separate delta host

- Status: Accepted
- Date: 2026-08-22

## Context

After ABI 8 the js-framework-benchmark integration still paid, per created
row, one `data-lrx-key` attribute write, one WeakMap lookup to find the cloned
template, and one `Set` insertion that existed only to detect repeated new
keys; every row of a table rebuilt from scratch was attached to a connected
parent one insertion at a time; and every application shipped the opt-in
structural-delta adapter inside `leanrx_region.mjs` although only the Data
Grid imports it. None of these costs involves the checked Lean models.

## Decision

The internal JavaScript runtime ABI becomes version 9 for every artifact.

The DOM host's `cloneTemplate(template)` now deep-clones a prototype node that
generated code built once (the benchmark `mount` builds the row template and
threads it through the keyed-item context), and the host adds
`setKey(node, key)`, which records a delegated key on a node as a JavaScript
property instead of an attribute. `listenDelegated` resolves the key of the
nearest ancestor-or-self of the action node, up to the registered root, from
either that property or a `data-lrx-key` attribute, so existing attribute-based
artifacts keep their behavior.

The keyed region validates a target through its key index alone: a retained
key is matched by position first and by the index otherwise, a new key
registers an unmounted entry, and a repeated key unregisters the new entries
and fails before any callback or DOM mutation. When no entry is retained, the
region rebuilds: previous rows are disposed, a region that owns its whole
parent clears it with one bulk removal and, while that parent is connected, not
the active element, and about to receive rows, detaches the parent for the
bulk insertion and restores it at the same position, so the browser attaches
the rebuilt subtree once. Unowned parents, pure clears, and updates with any
retained row never detach anything. Placement counts are unchanged.

`createDeltaKeyedRegion` moves to `runtime/leanrx_delta_region.mjs`, which
imports the shared anchor, detach, placement, and rebuild helpers from
`leanrx_region.mjs`; its full reconcile uses the same rebuild path. Artifacts
that do not use structural deltas no longer ship the delta validator.

## Consequences

ABI-8 and ABI-9 artifacts/hosts must not be mixed. All manifests move to
version 9. The Data Grid manifest adds `./leanrx_delta_region.mjs` to its host
imports and its build copies the module; `leanrx doctor` checks for it. A
briefly detached parent is observable by mutation observers on the parent's
container and by custom-element reactions on the parent; it is accepted only
under the ownership, connection, focus, and non-empty-target guards above and
is recorded here rather than hidden. The DOM/region hosts, generated code, and
browser remain in the trusted computing base; the pure region theorems do not
cover the rebuild or placement algorithms.

## Validation

Fake-DOM tests lock the detach/restore count and parent position across first
fill, replace-all, retained update, pure clear, focused parent, and foreign
sibling cases for both keyed regions, alongside the existing placement, bulk
clear, duplicate-key fail-before-mutation, and fuzz checks. Delegated-key
resolution through a row-root property and through an action-node attribute is
exercised by the js-framework-benchmark and TodoMVC browser gates. The upstream
benchmark run records the new durations and the smaller shipped size in
`BENCHMARK.md`.
