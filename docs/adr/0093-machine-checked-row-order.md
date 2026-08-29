# ADR-0093: The key order is checked by the compiler, not by review

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0092 resolves a dispatching key to its position by binary search, and the
search is exact for exactly one reason: a region's row table is **strictly
ascending in `row[0]`** at every point a transaction can observe it. That ADR
argued the property site by site — both `push` sites take `regions[r][2]` and
then increment it, no emission assigns a row's key slot again, every removal
preserves the order of the rows it keeps, and the component backend has no
swap, no sort and no insert-at — and then wrote its own first open question:

> The order invariant is enforced by review and by witness, not by the type
> system. Nothing in Lean stops a future emission from pushing a row at a
> position, sorting a table, or exposing `swapAt` to the component backend,
> and any of those silently breaks every search. […] A structural check over
> the emitted AST […] is possible and was not written: it would restate the
> enumeration above in a second place, and the round judged the witness the
> more honest of the two.

This round judges the other way, and the reason is that the sentence quoted
above mis-describes what the check would contain.

### Why "it restates the enumeration" is wrong

ADR-0092's argument is a table with **one row per emission site**: `append`,
`hydrate`, the update stage, `broadcast`, `remove`, a guard hit, `removeIf`,
the filter sweep, the `updateAt` drain. That table grows every time the
backend learns a new action, and every new row is a fresh obligation to
re-derive by hand.

A structural check is not that table written twice. It is a much shorter list
with **one rule per thing that can happen to a JavaScript array**: something
enters it, something leaves it, an element is replaced, the whole array is
replaced, a method reorders it, an alias escapes to code the check cannot
see. That list is closed — JavaScript has no seventh way to disturb an
array's order — and it does not grow when a tenth emission site appears,
because the tenth site can only reach a row table through one of the six.
The 2026-08-29 emission needs eight rules to be spelled precisely; a future
one with twice the sites needs the same eight.

So the two artefacts are not the same content in two places. One is a proof
sketch over today's sites; the other is a decision procedure over all
possible ones. ADR-0092 declined the second because it looked like the first.

### The other reason: the browser gate cannot cover what does not exist yet

ADR-0092's nine-cell Toggle Lab gate is a good witness and it stays. What it
witnesses is *Toggle Lab*. A component with a new row action, or a region
shape no example exercises, has no cell anywhere; the emission that breaks
the order is the emission nobody wrote a gate for. An audit that runs inside
`Backend.Component.emit` witnesses every module the compiler will ever
produce, including the ones written after this ADR.

### Which layer

Two layers were on the table.

**Narrow the emission helpers** so only the order-preserving shapes are
constructible — a `RowTableOp` vocabulary with `pushFresh`, `spliceAt`,
`rebuildKept` and nothing else. Declined, and not because it is more work: it
is not *checkable*. `Stmt.assign`, `Expr.call` and `Expr.index` are the
general JavaScript AST every backend builds with, they cannot be taken away,
and a future author who does not use the narrowed vocabulary gets no
diagnostic — only a convention they never read. A vocabulary constrains the
paths that opt in; the paths that break the order are precisely the ones that
did not.

**Audit the emitted module**, which is what this ADR does. Every statement
every emission path produces ends up in one `Js.Module`, and the audit runs
on that module in the one place it is assembled, immediately after
`Module.validate`. There is no opting out, because there is nothing to opt
into: a new emission path is audited by existing.

## Decision

**`Backend.Component.emit` audits the module it just built for every shape
that could break a row table's key order, and rejects the emission if it
finds one.** The audit lives in `LeanRx/Backend/RowOrder.lean`, is
parameterised by the component's region slot, and reports every violation
under one new code, `LRX-BE-036`.

Eight rules. The first establishes that the audit sees every row table; the
rest say what may be done to one.

* **R0 — every row table in the module is spelled `regions[r][1]`.** No
  expression indexes the context twice, the context's region slot binds only
  to the name `regions`, and the mounted `context` literal carries exactly
  that binding at that slot. This is what makes the audit's reach a fact
  rather than a hope: a second name for the record cannot be minted.
* **R1 — a row table occupies only approved positions**: the object of a
  `push`, a `splice` or a `length` read, the iterable of a `for`-of, the
  object of an element read, an argument to its own region's host handle
  method or to `$lrx_row_seek`, or the target of a whole-table assignment.
  An aliasing `const`, a `sort`, a `reverse`, an `unshift`, a return, an
  array element — all rejected.
* **R2 — a `push` onto a row table takes one argument**, an array literal
  whose head is `regions[r][2]` for the same region. A row cannot enter under
  a borrowed, stale or constant key.
* **R3 — a `splice` on a row table takes two arguments and removes exactly
  one row**, so it cannot insert and cannot take a neighbour with it.
* **R4 — nothing overwrites a key.** No row is replaced in place
  (`regions[r][1][i] = …`), no key slot is assigned through a row binding, a
  direct element read or *any function parameter*, and no region record is
  replaced wholesale.
* **R5 — a whole-table assignment is the ADR-0050 kept filter and nothing
  else**: the assigned identifier is declared `const k = []`, pushed exactly
  once with the binding of a `for`-of over the very table it replaces,
  installed exactly once, and used nowhere else.
* **R6 — the key counter only advances**: `regions[r][2]` is assigned nothing
  but `regions[r][2] + n` with `n ≥ 1`, for its own region.
* **R7 — a region mounts with an empty table and a zero counter**, so the
  first key a region ever mints is below every key it will mint later.

Three notes on the edges.

**R4's parameter half is deliberately broader than rows.** The audit cannot
tell a row parameter from any other array parameter, so it forbids writing
slot 0 of *every* parameter. The emission pays nothing for that — no
generated function writes any parameter's slot 0 — and it closes the one hole
a purely local analysis would otherwise leave: a row that reached a function
as an argument.

**R5 leans on `LRX-BE-018`.** Because the pushed value must be the binding of
a `for`-of over the table, the module validator's existing scoping rule
already places the push inside that loop; the audit does not re-derive
scoping.

**The audit does not cross into the host.** `createKeyedRegion`'s handle
receives a table by R1's argument allowance and could in principle reorder
it. That side is pinned by `runtimeAbi` and by the region-runtime gate, and
this is the boundary a future round would have to move if the host ever gains
a reordering export. The hand-written backends — Todo, Notes, Issue Browser,
Data Grid, the js-framework-benchmark — carry no region record and no
`$lrx_row_seek`, so neither ADR-0092's search nor this audit applies to them.

### The diagnostic

**`LRX-BE-036`, one code, raised by the component backend at emission**, in
the same `Except Error` the module validator already uses — so it surfaces
exactly where `LRX-BE-018` does, as a failed `lake exe leanrx_*_js` rather
than as a browser gate five minutes later. The message names the rule and the
function: `row order audit (R3) in '$lrx_region_0_dispatch': region 0's table
takes a splice that is not a single-row removal`. One code rather than eight,
because the *reader* who trips this needs to know which of the eight shapes
they emitted and where, and the rule tag in the message carries that; a
caller has no reason to branch on which one.

### Cost

**718 µs per audit of Toggle Lab**, the largest generated module (168 kB,
4 700 printed lines), measured compiled over 200 repetitions; Mix Lab is
smaller. Across the twenty component-backend generator runs in
`scripts/check_component_codegen.sh` — the other fourteen are hand-written
backends that emit no region record — that is under 15 ms in total, and the
wall time of `lake exe leanrx_toggle_js` is 0.53–0.55 s with the audit and
0.53–0.55 s without it — the check is below the measurement floor of the
thing it runs inside. The audit is one traversal of the module collecting an
identifier census, plus one scan of that census per whole-table assignment,
of which a module has at most a handful.

**Zero output bytes.** The audit reads the module and returns; it does not
build one.

### Witness

Toggle Lab's emitted module *is* the fixture. Twenty-two cases each take the
module `Backend.Component.emit` really produced and inject one order-breaking
statement into one of its real functions — `$lrx_region_0_dispatch` for most,
`$lrx_region_0_row` for the parameter rule, the `mount` record literal for
R7 — then demand the audit rejects it *under the named rule*. The three
futures ADR-0092 OQ1 worried about appear by name: a row inserted mid-table
(a three-argument `splice`, R3; an `unshift`, R1), a sorted table (R1), and a
swap in each spelling it has (an element replaced in place and two key writes,
R4). Two more assert the audit **accepts**: the unmodified module, and an
injected order-preserving rebuild — so R5 is a shape rule and not a ban on
touching the table.

Both directions were checked against deliberate breakage rather than assumed
to bite.

- *The emitter, broken twice.* Changing the sealed removal's `splice` to a
  three-argument insert and changing the append's key from `regions[r][2]` to
  a constant each make `lake exe leanrx_toggle_js` exit non-zero with
  `LRX-BE-036`, so the audit is wired into the path that produces bundles and
  not merely into a test.
- *The audit, broken twice.* Deleting R4's element-replacement rejection
  turns the witness red with `accepted an order-breaking emission: a row
  replaced in place`. Making `rowTable?` blind — the vacuity failure mode, an
  audit that quietly stops recognising row tables — does not silently pass:
  the *real* Toggle Lab emission then fails R5, because a rebuild the audit
  can no longer classify is a rebuild it cannot accept. The audit's fail-safe
  direction is to reject.

## Consequences

- **Every generated file in every bundle is byte-identical.** Proven by
  generating Toggle, Mix, Twin, Branch and Nest Lab from the pre-change
  emitter under `git stash`, regenerating after, dereferencing both symlinked
  bundles with `cp -RL` and comparing with `diff -rq`: no difference in any
  `.mjs`, `.graph.json` or `.manifest.json`. The benchmark size gate,
  BENCHMARK.md and the js-framework-benchmark backend stand untouched for the
  same reason ADR-0092 left them: nothing they emit changed.
- **No host change and no ABI move**: `runtimeAbi` stays **17**. The audit is
  a compile-time reader; it exports nothing and imports nothing at runtime.
- **ADR-0092 OQ1 is closed.** Its replacement obligation is narrower and
  stated here: a future round that lets the host reorder a table it was
  handed, or that reshapes the region record's context plumbing, has to
  reopen R0/R1 by name.
- `Backend.Component.regionSlot` becomes public, because the audit is
  parameterised by it and the witness re-runs the audit from outside the
  namespace.
- ADR-0092's nine-cell browser gate is unchanged and still earns its place:
  it witnesses that the *runtime* behaviour follows from the order, which no
  static rule can say.

## Open questions

1. **The host is still review-checked.** R1 lets a table reach
   `createKeyedRegion`'s handle and `$lrx_row_seek`, and the audit stops at
   the call. `$lrx_row_seek` is generated three hundred lines away and reads
   only; the handle is `leanrx_region.mjs`, pinned by `runtimeAbi` and by
   `check_region_runtime.sh`. Nothing checks *that* the host does not
   reorder, and the cheapest thing that would is a rule over the host source
   rather than over the emission — a different layer with a different gate.
2. **`storageSet` and the `join` are the floor, at 35% each** (ADR-0087 OQ1,
   ADR-0088 OQ2, ADR-0092 OQ2, unmoved).
3. **A shared predicate pass is per commit, so it is not a cache**
   (ADR-0088 OQ3, ADR-0092 OQ3, unmoved).
