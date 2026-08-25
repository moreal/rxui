# ADR-0043: Sealed row expressions and row field updates through updateAt

- Status: Accepted
- Date: 2026-08-25

## Context

ADR-0041 sealed keyed-region rows behind a row binder whose only dynamic node
is a bare field projection and whose action vocabulary is exactly `remove`, so
rows are immutable after mount and the generated retained-row update callback
is a no-op. ADR-0040 stage 2 needs the next two capabilities on the TodoMVC
gate list — row field mutation (the `updateAt` path) and richer dynamic row
content — without reopening the decision ADR-0041 protects: `RxExpr`,
`DepSet`, and the propagation proofs stay untouched, and rows never observe
component state after mount.

## Decision

1. **Sealed `RowExpr`.** Dynamic row content generalizes from a bare field
   projection to a closed staged expression over the row tuple:
   `RowExpr.lit`, `RowExpr.field`, and `RowExpr.append` (string
   concatenation). The language is deliberately `String`-only and mirrors the
   *shape* of `RxExpr` without touching it — no dependency sets, no schema,
   no proofs. Row templates gain `RowNode.exprText`; a `{field}` child keeps
   lowering to `RowNode.fieldText` (the degenerate projection), and
   `{a ++ " " ++ b}` lowers to `exprText`. Field references are bounds-checked
   against the region's declared fields (`LRX-VIEW-026`), and the surface
   accepts exactly bare row fields, string literals, and `++`
   (`LRX-ELAB-115` otherwise); `s!"…"` interpolation stays term-level `rx%`
   territory and is not admitted into row scope.
2. **Row update actions.** `RowAction` gains `update` — a nonempty list of
   simultaneous assignments `field := RowExpr` evaluated against the
   dispatching row's current fields (all right-hand sides read the old
   tuple, then all targets are written). The surface declares one with a
   `row` item, `row roster mark := set marks (marks ++ " ★");`, and row
   templates opt in with the usual `onClick={mark}` reference. Validation
   requires a declared region, in-bounds distinct targets, and in-bounds
   expression fields (`LRX-VIEW-031`, `LRX-ELAB-115`). `remove` stays the
   only structural action; update actions never change row count, order, or
   keys.
3. **`updateAt` on commit.** The region record grows one slot —
   `[handle, items, nextKey, dirty, pending]` — and an update dispatch
   resolves the dispatching row by key scan, writes the new field values into
   the retained item in place, and pushes the row's position onto `pending`
   inside the ordinary transaction shell (trace `region:{name}:{event}`).
   The commit sweep drains `pending` after the dirty check: a structurally
   dirty region reconciles wholesale exactly as before (the full `update`
   re-runs every retained row, so pending entries are cleared unrendered),
   and an update-only transaction emits one `handle.updateAt(position,
   items[position], null)` per pending entry (trace
   `region:{name}:updateAt`). `updateAt` re-checks the key at the position
   (LRX-REGION-003), so a desynchronized items mirror throws instead of
   retargeting another row.
4. **Generated retained-row updates.** A region that declares at least one
   update action gets a real update callback: it re-renders every
   `fieldText`/`exprText` position by structural `childAt` navigation from
   the row root and unconditional `setText` — the same navigate-and-write
   shape `Backend.Todo`'s bespoke row update already uses. Regions without
   update actions keep the generated no-op callback, so ADR-0041-style
   emission is unchanged for them apart from the widened region record.
5. **No ABI change, byte identity.** Every host export used — `childAt`,
   `setText`, `updateAt` on the region handle — predates this ADR; the
   runtime ABI stays 15. Components without regions emit byte-identical
   modules and manifests.

## Consequences and limitations

- Row text now reacts to row field updates end to end in the `component`
  command: declare the fields, bind a `row` event, and the delegated click
  re-renders exactly the dispatching row through `updateAt`.
- The retained-row callback re-renders every dynamic position of a row it is
  invoked for (no per-position caching); structural reconciles therefore
  rewrite retained rows' text with equal values, which the WHATWG equal-value
  text write makes observably free, matching the bespoke Todo precedent.
- `RowExpr` remains `String`-only concatenation: no numeric row fields, no
  predicates inside text, no component-state reads. Counters rendered from
  rows stay parent-owned. Row-scoped attribute selection is ADR-0044;
  conditional structure inside rows and typed payload row events remain on
  the ADR-0040 gate list.
