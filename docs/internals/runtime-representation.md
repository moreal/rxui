# Runtime representation contract

The runtime ABI is closed and indexed: callers may supply a local
`RuntimeRep`, but its `RuntimeType α` index prevents mapping a source type to a
different JavaScript category.

| Lean type | Runtime code | JavaScript representation | Equality plan |
|---|---|---|---|
| `Bool` | `bool` | `boolean` | strict |
| `String` | `string` | `string` | strict |
| `Int` | `int` | `bigint` | BigInt |
| `Nat` | `nat` | non-negative `bigint` | BigInt |
| `Vector α n` | `vector<α,n>` | array of the element representation | structural |
| `Fin n` | `fin<n>` | non-negative `number` index | strict |

For `Vector`, the runtime array contains only element values: the static length
and constructor evidence are erased. For `Fin`, only the numeric value remains;
the bound and proof that the value is below it are erased. Runtime type metadata
retains the length/bound so lowering can validate a whole expression before
emission, but generated values do not carry those numbers as proof objects.
Lean-checked constructors and typed vector access are therefore part of the
safety contract; foreign callers may not manufacture unchecked indices.
`RxExpr.vectorGet` requires the vector and `Fin` expression to share the same
length index. Lowering retains that relation through typed Reactive IR and emits
one JavaScript array access; the logical operation needs no runtime bounds
branch. Native-to-Node differential cases execute the first and last valid
indices in both printer modes.

One hand-lowered backend departs from the `Nat` row: the js-framework-benchmark
backend represents its model's row ids as safe-integer `number`s because that
application's id domain is bounded by its own specification (ADR-0029). The
general component compiler and every other backend keep the `BigInt` mapping.

`ReactiveIR.Expr.erasureReport` traverses every closed IR constructor, records
the vector lengths and finite bounds removed by the ABI, and separately records
any operation that would inspect such evidence. The scalar emitter invokes the
fail-closed `assertErasureSafe` gate before producing a JavaScript AST. The named
theorem `erasureReport_no_inspections` establishes that every expression in the
current closed IR reports no evidence inspection; its exact reviewed axiom
footprint is `[propext]`. This proves a property of the typed IR and analyzer,
not that the trusted JavaScript printer or engine implements erasure correctly.

The M3 scalar backend emits ESM functions whose parameters and returns use the
representations above. Each input position has a declared runtime code, and the
backend rejects any Reactive IR occurrence whose index is out of bounds or whose
runtime code disagrees with that signature. It imports no Lean runtime. `Int.toString` and
`Nat.toString` lower to JavaScript `String(BigInt)` and return decimal strings.

The backend does not emit raw JavaScript operators where Lean semantics differ:

- Lean `Int` modulo is Euclidean: `(-7) % 5 = 3`; JavaScript BigInt remainder
  would produce `-2n`.
- Lean `Int` and `Nat` modulo by zero return the dividend; JavaScript BigInt
  remainder throws.
- Lean `Nat` subtraction clamps at zero.

Generated private helpers implement these differences. `Int.mod` normalizes by
the absolute divisor, so both positive and negative divisor cases agree with
Lean; a zero divisor returns the dividend. `Nat` inputs are an ABI contract:
callers must provide non-negative BigInts.

Native-to-Node differential tests cover every supported scalar primitive,
negative and above-2^53 values, both divisor signs, zero divisors, clamped
subtraction, Unicode/control strings, conditionals, and display conversion. The
modules are generated from staged `RxExpr` values, so the gate includes Core to
Reactive IR lowering, and Node executes both readable and compact printer modes.

Every emitted scalar module has deterministic adjacent JSON metadata containing
the compiler version, exact Lean toolchain, module filename, runtime ABI version,
actual allocated export, ordered source/generated input names and runtime codes,
result runtime code, and the `scalar` feature marker. The runtime ABI is currently
version 17. Toolchain or ABI upgrades must update `LeanRx/Core/Version.lean`, this
document, manifest goldens, and the full differential/determinism gates together.
Generated JavaScript remains in the documented trusted computing base; these
tests are executable evidence, not a formal backend verification claim.
`RuntimeEq.jsPlan` is derived from `RuntimeType`; callers cannot pair an object
representation with JavaScript identity equality while claiming structural Lean
equality.

The M4 component ABI is also explicit. A component manifest records the ordered
runtime code for every state-array slot, the source-prefix and derived counts,
text-sink and event counts, exact host imports, exported `mount`, graph hash,
compiler/toolchain versions, and runtime ABI. The generated module owns the
state array in schema order. M5 private event handlers receive a mount-local
context containing that state, depth-first text refs, private transaction control,
changed flags, and sink caches; they update direct text nodes through `setText`.
`mount(target)` owns the mounted root and listener-disposal closures and returns
an idempotent disposer whose instrumentation accessor copies counters and trace.
The host modules integrate DOM and
effects only: they do not discover dependencies or schedule reactive work.
ABI 5 additionally exposes a fixed delegated-region event payload and a separate
local region reconciler; neither host discovers reactive dependencies or executes
application updates.

ABI 6 appends owned-command start and cancellation counters to the standard
copied instrumentation snapshot. Effect adapters receive explicit state,
context, handle, decoder, and delivery functions; structured foreign-port wire
types remain manifest-only and cannot enter the scalar reactive ABI. Their
type-indexed `PortRep` evidence and nominal `PortRecord` wrappers keep manifest
metadata aligned with the Lean input/output signature.

ABI 7 adds the checked structural-delta keyed-region adapter. It accepts only a
closed, compiler-generated delta vocabulary and validates the complete batch
before mutating owned DOM. The adapter remains a local region reconciler: it
does not discover dependencies, schedule reactive work, or interpret arbitrary
application messages.

ABI 8 adds `firstChild`, `nextSibling`, and `cloneTemplate` to the DOM host so
a generated static row template is built once and deep-cloned per instance,
resolves delegated `data-lrx-key` values from the nearest keyed ancestor-or-self
of the action node, and makes keyed placement minimal (prefix/suffix trim plus
a longest order-preserving subsequence, with one bulk clear when a region that
owns its whole parent drops every row). See
[ADR-0018](../adr/0018-runtime-abi-v8-template-clone.md).

ABI 9 makes `cloneTemplate` clone a prototype node that generated code built
once, adds `setKey` so a delegated key can live on a node as a property (the
delegated adapter resolves the nearest ancestor-or-self key from that property
or a `data-lrx-key` attribute), validates keyed targets through the key index
alone, rebuilds a region that owns its whole parent with one bulk clear and one
detached bulk insertion, and moves `createDeltaKeyedRegion` into
`leanrx_delta_region.mjs`, which imports the shared placement helpers from
`leanrx_region.mjs`. See
[ADR-0019](../adr/0019-runtime-abi-v9-owned-parent-rebuild.md).

ABI 10 forwards the context given to a keyed region's `update` (and the delta
region's `apply`) unchanged to the mount, update, and dispose callbacks as a
trailing argument, adds `updateAt(index, item, context)` to the keyed region
for re-running the update callback of one retained position whose key must
match, registers each key added to an empty keyed region with one index
insertion, and moves the conditional and positional regions into
`leanrx_unkeyed_region.mjs` (importing the shared anchor/detach/snapshot
helpers), which only TodoMVC imports. See
[ADR-0020](../adr/0020-runtime-abi-v10-keyed-context-and-update-at.md).

ABI 11 moves the typed control-event adapters `listenValue`, `listenChecked`,
`listenKey`, `listenFocus`, and `listenSubmit` (ADR-0013) unchanged from the
DOM host into `leanrx_form_events.mjs`; the DOM host keeps node construction,
traversal, mutation, `setProperty`, `uniqueId`, the generic `listen`, and the
delegated-event adapter (`setKey`, `listenDelegated`). Backends that lower a
`ControlEvent` import and list the new host; artifacts that only delegate events
ship the smaller DOM host. See
[ADR-0021](../adr/0021-runtime-abi-v11-form-events-host.md).

ABI 12 moves `makeDisposer` unchanged from `leanrx_host.mjs` (deleted) into the
DOM host, so every artifact imports its disposer from the module it already
fetches; the host comments are condensed to the terse style of the other hosts
and the keyed-region contract below is the reference for the prose they held.
See [ADR-0022](../adr/0022-runtime-abi-v12-disposer-in-dom-host.md).

ABI 13 adds two more targeted operations to the keyed region, alongside
`updateAt`: `swapAt(first, second, items, context)` exchanges the retained rows
at two positions with at most two node moves (one when adjacent) and re-runs
the update callback for exactly those positions, and `removeAt(index, key,
context)` disposes and detaches one retained row while the later rows shift a
position without an update callback; both check their keys before any callback
or DOM mutation (`LRX-REGION-003` otherwise). See
[ADR-0026](../adr/0026-runtime-abi-v13-keyed-swap-and-remove.md).

ABI 14 adds `nextText(node)` to the DOM host: the Text node that follows
`node` in document order (descendants first), or `null`, through one shared
`TreeWalker(SHOW_TEXT)` whose `currentNode` is the last returned node; it does
not stop at `node`'s subtree, so generated code uses it only where a static
template guarantees the text slots it addresses. A cloned template's text
slots are reached without wrapping the elements between them (three wrappers
per js-framework-benchmark row instead of six). See
[ADR-0028](../adr/0028-runtime-abi-v14-next-text.md).

ABI 15 adds `listenDelegatedCells(node, type, state, context, dispatch,
actions)` to the DOM host: a delegated listener for keyed rows that resolves
the action from structure instead of an attribute — the row is the nearest
ancestor-or-self of the event target (within `node`) marked by `setKey`, and
the action is `actions[i]` where the row's child at `childNodes` index `i`
contains the target strictly inside it (an empty or missing entry, a target
that is that child itself, or no keyed row dispatches nothing); `dispatch`
receives the same arguments as `listenDelegated`'s, with the row's key. Rows
cloned from a template therefore carry no per-row `data-lrx-action`
attributes, and the benchmark's button row is marked the same way so its six
buttons dispatch by wrapper position (ADR-0032). `listenDelegated` is
unchanged for attribute-marked controls. See
[ADR-0030](../adr/0030-runtime-abi-v15-structural-delegation.md).

ABI 16 adds `focus(node)` to the DOM host: it moves keyboard focus to `node`
(the WHATWG `focus()` steps). Generated code calls it from exactly one site —
the retained-row update callback's branch replacement arm, on the freshly
mounted branch subtree's `autoFocus`-marked input — so focus transfers when a
user action swaps in an edit affordance, while row mount, reorder, and
stable-branch updates never touch focus. See
[ADR-0048](../adr/0048-row-focus-vocabulary.md).

ABI 17 adds the routing and persistence hosts to the DOM host (ADR-0063):
`readHash()` returns `location.hash` (called once at mount to seed the routed
state field); `listenHash(state, context, dispatch)` registers one
`hashchange` listener in the `listen(...)` style — the host builds the closure
because generated code has none — calling `dispatch(state, context,
location.hash)` per event and returning a removal closure that joins the
mount's `listenerDisposers` array explicitly (the first listener whose
lifetime is not rooted in the mounted subtree); `writeHash(value)` assigns
`location.hash` (generated code writes it flip-only behind the routed field's
changed flag, and a WHATWG equal-value assignment fires no `hashchange`, so no
echo loop exists); and `storageGet(key)`/`storageSet(key, value)` move one
string through `localStorage` synchronously — serialization lives in generated
code as a throw-free split/join escape, so the hosts stay dumb and a
hand-edited stored value fails closed instead of failing the mount. All five
exports are reachability-gated in the component import emission and are plain
prunable function declarations with no module-level state and no
compactor-rejected construct, so a component (and the benchmark bundle) that
declares no route or persist item emits byte-identical JavaScript. See
[ADR-0063](../adr/0063-freeze-boundary-routing-persistence.md).

The keyed region host (`leanrx_region.mjs`) exposes `createKeyedRegion(parent,
mountItem, updateItem, disposeItem, rootItem?)` to generated code and shares
`detach`, `anchor`, `snapshot`, `placeInOrder`, and `rebuild` with the delta and
unkeyed region hosts; of those, only `detach` is also a generated-code entry
point — a component module whose row templates carry ADR-0047 branch cells
imports it beside `createKeyedRegion`. Such a module mounts each branch cell
as one wrapper element holding the selected sealed subtree, records the
rendered branch on the wrapper as the `$lrxBranch` marker property (the
`setKey`/`$lrxKey` style, written through `setProperty`), and its retained-row
update callback replaces a changed branch with one `detach` of the old subtree
plus one `append` of the freshly built one — a generated-code convention over
existing exports, not an ABI change. `update(items,
context)` reconciles the whole target, where `items[i][0]` is the key: it
validates every key before the first callback or DOM mutation, matching a
retained key by position first (no hashing while the order is unchanged); the
first key away from its position decides the rest: keys that are all numbers,
all bigints, or all strings and strictly increasing or decreasing are pairwise
distinct, so the key index (built from the previous rows when an update first
needs it, joined by every new key while it exists, dropped whenever nothing is
retained) is consulted only while a previous row is still unmatched and fills,
appends, and replacements in key order hash nothing; otherwise every key away
from its position is looked up and a repeated key drops the index and throws
`LRX-REGION-001`; it then forwards `context` to
`mountItem(item, index, context)`, `updateItem(handle, item, index, context)`,
and `disposeItem(handle, key, context)`. `updateAt(index, item, context)`
re-runs `updateItem` for one retained position whose key must match
(`LRX-REGION-003` otherwise) and changes no shape, order, or identity;
`swapAt(first, second, items, context)` requires `items` to differ from the
current order only by the exchange of positions `first < second` (so
`items[second][0]` is checked at `first` and `items[first][0]` at `second`),
moves the higher node before the lower one and, unless they are adjacent, the
lower node before the old successor of the higher one, then re-runs
`updateItem` for both positions; `removeAt(index, key, context)` disposes the
retained row at `index` (whose key must be `key`), detaches its node, and
unregisters the key from an existing index, and the later rows keep their
handles and nodes one position earlier without an update callback. A backend
that lowers an operation through one of these must argue that the result
equals a full `update` (no other row's render payload changed, and for
`removeAt` no row's payload depends on its position).
Placement inserts new nodes and moves only the retained nodes outside one
longest order-preserving subsequence after trimming the unchanged prefix and
suffix, so a two-row swap costs two DOM moves; ties keep earlier target
positions in place. When nothing is retained, a region that owns its whole
parent (its first node through its marker, no foreign sibling) removes the old
rows with one bulk clear and, while the parent is connected, not focused, and
about to receive rows, detaches that parent so the browser attaches the rebuilt
subtree once instead of per row.

Dynamic-region manifests use a separate `ManifestTypeId` for metadata-only
`record<name>` and `list<element>` slot descriptions. Those constructors cannot
enter `RuntimeTypeId`, graph equality planning, or Reactive IR. They do not
create public `RuntimeRep` instances or make arbitrary Lean structures
browser-lowerable; a specialized checked backend must own and document each
actual array/record layout. Todo items use the M8-specific array layout
documented with the Todo backend.
