# ADR-0041: Sealed row binders for generic keyed region slots

- Status: Accepted
- Date: 2026-08-25

## Context

ADR-0040 proposed region slots in the safe view but left its largest question
open: rows are dependent (each row reads its item, not the component state),
so either rows get their own `Schema` with an embedding into `RxExpr`, or a
sealed row-scope binder outside `RxExpr`. The embedding would thread a second
scope through `Field`, `DepSet`, the dependency index, and the propagation
proofs — exactly the kernel-adjacent machinery the safety argument rests on —
to serve a first milestone that only needs a row text position and a row
click.

## Decision

Rows bind through a **sealed row binder**, not a schema embedding:

1. **Row model.** A `RegionSpec` declares a name, an array of `String` row
   fields, a sealed row template, and a closed row event table. The template
   (`RowNode`) is a restricted view whose only dynamic node is
   `RowNode.fieldText i` — a typed positional projection of the row tuple —
   and whose events reference the sealed vocabulary. `RxExpr`, `DepSet`, and
   every proof stay untouched.
2. **Sealed row events.** `RowAction` is a closed inductive; stage 1 contains
   exactly `remove` (dispose the dispatching row). Every region declares the
   `remove` row event; templates opt in with `onClick={remove}`. Rows are
   immutable after mount (no row mutation exists in the vocabulary), so the
   retained-row update callback is a generated no-op.
3. **Region-owned keys.** `append region (expr, …)` — the new `Update.regionAppend`
   constructor — pushes `[nextKey, field…]` and increments a per-region
   monotone counter that lives entirely inside the mount context. Keys are
   safe-integer JavaScript numbers (ADR-0029) that user code can never forge
   or duplicate, so the LRX-REGION-001 uniqueness invariant holds by
   construction and the ADR-0027 monotone fast path applies.
4. **Mount context.** Region records ride the context after the prop slots
   (`context[6]`, or `context[8]` when reflected properties exist), one
   `[handle, items, nextKey, dirty]` record per region in declaration order.
   The commit sweep runs after text and property sinks and calls
   `handle.update(items, null)` only when the dirty flag is set. `tx` keeps
   its ten slots; region activity is visible in the trace
   (`region:{name}:append/remove/update`) and through
   `disposer.regionInstrumentation()`, which now receives the generic
   backend's region handles.
5. **Structural delegation.** Row events lower to one
   `listenDelegatedCells(container, "click", …)` listener per region
   (ADR-0030/0032): the cell action array maps row-root child indices to row
   event names, and validation requires the bound button to sit strictly
   inside a row cell (`LRX-VIEW-027`) so the runtime can resolve the action
   from structure alone — no `data-lrx-action` vocabulary. The region slot
   must be the only child of its container element (`LRX-VIEW-029`), which the
   `<region name/>` view position and `createKeyedRegion`'s anchor marker rely
   on.
6. **No ABI change, byte identity.** Every host export used —
   `createKeyedRegion`, `listenDelegatedCells`, `setKey` — predates this ADR;
   the runtime ABI stays 15. Components without regions emit byte-identical
   modules and manifests (all eleven non-region dists diffed clean).
   Manifests disclose `keyed-regions` in `features` and
   `./leanrx_region.mjs` in `hostImports`; per-region counts stay out of the
   manifest (resolving ADR-0040's counting question as: static declarations
   only, and deferred).

New diagnostics: `LRX-VIEW-025` (region table/reference), `LRX-VIEW-026` (row
fields/projections), `LRX-VIEW-027` (row template structure), `LRX-VIEW-028`
(row event references), `LRX-VIEW-029` (region placement), `LRX-TYPE-109/110`
(append target/arity), `LRX-ELAB-111/114` (region item surface). Nest Lab
dogfoods the surface end to end and Chromium gates append order, delegated
removal by key, non-action clicks, and disposal.

## Consequences and limitations

- Keyed lists are now writable in the `component` command with no backend
  code, from surface syntax to delegated dispatch — ADR-0040 stage 1.
- Row-scope staged expressions remain unresolved by design: dynamic row
  content is sealed field projection only, rows are `String` tuples, rows are
  immutable after mount, and `remove` is the whole action vocabulary. The
  forward path is a sealed `RowExpr` language over row fields (mirroring
  `RxExpr` shape without touching it), row update ops feeding
  `updateAt`/`swapAt`, and richer payload kinds — none of which disturb this
  ADR's context layout.
- The positional filter region of TodoMVC is not expressible yet; ADR-0040
  keeps that question open for stage 2.
