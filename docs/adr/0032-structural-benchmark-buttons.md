# ADR-0032: Resolve the js-framework-benchmark buttons by structure

- Status: Accepted
- Date: 2026-08-23

## Context

ADR-0030 resolves the benchmark's row clicks by structure: the table body's
`listenDelegatedCells` listener maps the clicked cell's position to its
action and the cloned rows carry no `data-lrx-action` attributes. The six
buttons above the table still went through the attribute adapter — `mount`
registered `listenDelegated(target, "click", …)` on the page root, the
buttons carried `data-lrx-action` attributes beside their upstream ids, and
the flattened module therefore shipped `listenDelegated` and its
`delegatedKey` walk (the `closest`, `contains`, `$lrxKey`/`data-lrx-key`
resolution) for six static elements. After ADR-0031 those two functions were
the only attribute-path code left in the module: 459 raw / about 135
upstream-style Brotli bytes for a second delegation mechanism that the rows
no longer use.

The buttons already have a structure that determines the action: the page's
button row holds one wrapper per button, in a fixed order, and the upstream
ids of the buttons equal the backend's action slugs.

## Decision

The benchmark page's button row carries `id="buttons"` and its six wrappers
are adjacent (no whitespace text nodes between them) in the order of
`Backend.JsFrameworkBenchmark.buttonActions = ["run", "runlots", "add",
"update", "clear", "swaprows"]`; the build renders the wrappers from that
list, so the page and the backend cannot disagree, and the buttons carry no
`data-lrx-action` attributes. `mount` marks `#buttons` with `setKey(buttons,
"")` — a keyed row whose key no button action reads — and registers
`listenDelegatedCells(buttons, "click", state, context, dispatch,
buttonActions)` beside the table body's listener: a click strictly inside the
`i`-th wrapper dispatches `buttonActions[i]` with the key `""`, and a click on
the row or on a wrapper itself dispatches nothing. The backend no longer
imports `listenDelegated`. The DOM host, the runtime ABI (15), the Lean model,
the region host, TodoMVC, and the data grid (which keep the attribute adapter)
are unchanged.

## Consequences

The flattened module no longer contains the attribute adapter: `main.mjs`
shrinks from 8,942 raw / 3,251 upstream-style Brotli bytes to 8,479 / 3,115
and `index.html` from 1,666 / 360 to 1,458 / 337 (the application from
10,608 / 3,611 to 9,937 / 3,452, against Solid's single 11,563 / 4,358-byte
module). A button click now walks two `parentNode` steps instead of a
`closest` query and the key walk; the measured operations are unchanged
(their cost is in the handlers, not the dispatch). The benchmark page gains a
second required element (`#buttons` beside `#tbody`) and the wrapper order
becomes part of the page contract, which the build derives from the backend's
list; the page's button ids remain the upstream selectors.

## Validation

`Test/Backend/JsFrameworkBenchmark.lean` asserts the `setKey(buttons, "")`
mark, the structural button listener with the six actions, the absence of
`listenDelegated`, and the action order; the benchmark browser gate drives
every button through the new listener and checks that a click on the button
row or on a wrapper itself dispatches nothing; the size gate records the new
baseline. The upstream run recorded in `BENCHMARK.md` reports the size rows.
