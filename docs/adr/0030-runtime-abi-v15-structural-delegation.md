# ADR-0030: Bump the internal runtime ABI for structural row-click delegation

- Status: Accepted
- Date: 2026-08-23

## Context

Since ADR-0014 the DOM host's `listenDelegated` resolves a delegated event by
the nearest ancestor-or-self of the target carrying a `data-lrx-action`
attribute (and its key by the nearest `setKey` mark or `data-lrx-key`
attribute). The js-framework-benchmark's row template therefore carried two
such attributes per row — `select` on the label link and `remove` on the
remove link — and every cloned row copied both. The paired CDP sampling
profile of the create-10,000 handler after ADR-0027 and ADR-0028 attributed
about 0.4–0.6 ms of `cloneNode` self time to those attributes (measured by
deleting them, which broke the row clicks), the last structural difference
between LeanRx's row markup and the upstream vanilla implementation's besides
the keyed-row mark itself.

The row's structure already determines the action: a click strictly inside
the row's second cell is a select, strictly inside its third cell a remove,
and the row's key is the `setKey` mark on the row root. The buttons outside
the table keep their attributes in the page; they are six static elements.

## Decision

The internal JavaScript runtime ABI becomes version 15 for every artifact.

The DOM host gains `listenDelegatedCells(node, type, state, context, dispatch,
actions)`: a delegated listener for keyed rows that resolves the action from
structure. The row is the nearest ancestor-or-self of the event target (within
`node`) marked by `setKey`; the action is `actions[i]` where the row's child
at `childNodes` index `i` contains the target strictly inside it (an empty or
missing entry, a target that is that child itself, or no keyed row dispatches
nothing); `dispatch` receives the same seven arguments as `listenDelegated`'s,
with the row's key. `listenDelegated`, `setKey`, and the rest of the DOM host
are unchanged, so TodoMVC and the data grid keep their attribute-marked
controls.

The js-framework-benchmark backend builds the row template without action
attributes, registers `listenDelegatedCells(tbody, "click", state, context,
dispatch, ["", "select", "remove", ""])` beside the attribute listener that
serves the buttons, and disposes both. The Lean model, the keyed region host,
and every other operation are unchanged.

## Consequences

ABI-14 and ABI-15 artifacts/hosts must not be mixed. All manifests move to
version 15. A cloned benchmark row carries only the `class` attributes the
upstream contract requires: create 10,000 falls 0.63 ms locally (paired
medians, 16 clicks per page, 10 rounds, every round negative), create 1,000,
replace, and append about 0.05 ms each, while select is unchanged and remove
costs 0.01 ms more (the attribute listener's `closest` walk, which now finds
nothing on a row click, runs beside the structural one). A click on a row cell's
padding dispatches nothing, as before; a click anywhere strictly inside an
action cell dispatches that cell's action, where the attribute contract
required the click to land on or inside the marked link — for the benchmark
template the link is the cell's only child, so the two coincide. The DOM host
and the flattened benchmark module grow by the helper, so the size baseline
moves accordingly.

## Validation

The counter browser suite, which serves the DOM host directly, checks
`listenDelegatedCells` on real DOM: the dispatched action, key, and argument
shape for clicks inside the select and remove cells (link, icon), nothing for
the id and filler cells, for a cell or the row itself as the target, for an
unkeyed row, and for the listener's own node, and nothing after disposal. A
differential fuzz (not committed) clicked random elements of random
benchmark-shaped rows — with extra nesting inside the links, extra filler
children, and row-key overrides — against the previous host's attribute
resolution and compared the dispatch logs over several thousand clicks with
no difference. The js-framework-benchmark browser gate exercises selection,
removal, and the unknown-key precondition cases through the new listener; the
size gate and the upstream run record the results in `BENCHMARK.md`.
