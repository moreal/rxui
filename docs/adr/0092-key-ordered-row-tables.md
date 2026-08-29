# ADR-0092: A key resolves to its position by search, not by index

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0084 opened one question and ADR-0085, ADR-0086, ADR-0087 and ADR-0088
each restated it verbatim and moved on: **the dispatch's key→position
resolution is `O(N)`.** Every row event — the ADR-0043 update stage, each arm
of an ADR-0052 key selection, the sealed `remove` action, an ADR-0053 guard
hit — begins by walking the region's row table from the front comparing
`row[0] === key`, and the walk has no early exit. ADR-0088 named it precisely:
after the shared predicate pass it is *the only `O(N)` traversal in a
`toggle` commit that no contract requires*. The shared pass earns its walk
(it evaluates predicates over every row), the filter sweep earns its walk (it
compares every row's displayed state), the persistence write-back earns its
walk (one region's table is one string). This one earns nothing; it is
looking for a single row and reads every row to find it.

The exchange the five ADRs kept refusing was always stated the same way, and
it is worth quoting because the whole round turns on it: a key→index **map on
the region record**, in exchange for the `append`/`removeAt`/`updateAt`/
`broadcast`/`removeIf`/filter-sweep/`hydrate` invalidation matrix, which
ADR-0085 priced at 1.5× against seven invalidation sites.

### The premise the OQ carried, and why it is wrong

The proposal assumes that if a dispatch is to skip the walk, some structure
must *remember* where each key lives — and therefore that every mutation owes
that structure a maintenance step. That is true of a map from keys to
positions. It is not true of the thing actually needed, which is much weaker:
a way to *find* a position without reading every row.

A row table already contains one. **It is sorted by key**, and it is sorted
by key for reasons that were all sealed years of ADRs ago, none of which was
about searching:

| site | what it does to the table | why the order survives |
| --- | --- | --- |
| `append` (ADR-0041) | pushes `[regions[r][2], …]`, then `regions[r][2] += 1` | the pushed key exceeds every key in the table, and it lands last |
| `hydrate` (ADR-0063) | pushes every parsed row through the append path | same counter, same increment, so the stored order takes consecutive keys |
| update stage (ADR-0043) | writes fields at `row[target + 1]` | slot 0 is the key and no emission ever assigns it |
| `broadcast` (ADR-0050/0061) | writes every row's fields in place | same: no key is written and no row moves |
| `remove` / guard hit (ADR-0043/0053) | drops one row | the survivors keep their relative order |
| `removeIf` (ADR-0050) | keeps the rows failing a predicate | order-preserving filter |
| filter sweep (ADR-0051/0086) | writes `hidden` and the row's display cell | touches no key and no position |
| `updateAt` drain (ADR-0043) | re-renders one retained row | reads a position, writes none |

There is no `swapAt`, no sort, and no insert-at in the component backend's
vocabulary — the two `push` sites above are the *only* places a row enters a
table, and `nextKey` only ever increases. So a row table is strictly
ascending in `row[0]` at every point a transaction can observe it, and a
binary search over it is exact.

That reframes the exchange completely. The invalidation matrix is not the
price of the search; it is a **theorem about the emission**, one row per
column, and every cell reads "nothing to do".

### What this borrows from ADR-0027, and what it does not

ADR-0027 is the precedent and its title is the borrowed idea: *validate
monotone keys **without** an index*. The keyed region host declines to hash a
key whenever consecutive keys are strictly increasing, because strictly
increasing implies pairwise distinct. This ADR takes the same move one layer
up — monotone keys are enough, so no index — and applies it to a different
question (where is this key, rather than is this key a duplicate) in a
different backend.

What it does **not** borrow is everything ADR-0027 needs because it is a
*host*: the lazily built `Map` fallback for non-monotone callers, the
descending case, and the `<`-is-not-transitive-across-types restriction to
number/bigint/string keys. `createKeyedRegion` accepts whatever keys its
caller supplies, so it must survive arbitrary ones. A component's row table
has exactly one writer, `regions[r][2]`, which mints JavaScript numbers in
increasing order — so there is no non-monotone case to fall back to, no mixed
key type to be careful about, and no fallback code to carry.

### The survey: three rungs, three workloads

Same harness as ADR-0085‥0088 — the *generated* Toggle Lab module, hydrated
to N rows through the real storage path, 400 single-row dispatches per sample
with the whole loop timed and divided, Chromium's `performance.now()` still
clamped at 0.1 ms so nothing smaller than a whole loop is trusted. Median of
nine in-page repetitions, median of seven page loads. Unlike earlier rounds
the loads are **paired**: every rung is measured at each load index before
the next load begins, so machine drift lands on all three equally.

Three rungs: **R0** the emitted forward scan, **RS** this ADR's key search,
**RM** a key→index `Map` at region record slot 8 maintained by every
structural site — the literal ADR-0084 OQ2 proposal, built so the round could
price it rather than quote its old price.

Three workloads: `toggle` (a field write, drain class 0), `retype` (a field
write in a row editor, drain class 1 — the commit where the resolution's
share is largest because ADR-0084 keeps it out of every predicate scan), and
`churn` (one ✕ removal and one append per iteration, so the region keeps its
size and every rung pays its removal invalidation N times).

Milliseconds per commit, median of medians:

| workload | N | R0 emitted scan | RS key search | | RM key→index map | |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `toggle` | 1 000 | 0.0752 | **0.0723** | 1.041× | 0.0715 | 1.052× |
| `toggle` | 10 000 | 0.6313 | **0.6095** | 1.036× | 0.6065 | 1.041× |
| `retype` | 1 000 | 0.0617 | **0.0597** | 1.033× | 0.0602 | 1.025× |
| `retype` | 10 000 | 0.5430 | **0.5088** | 1.067× | 0.5073 | 1.070× |
| `churn` | 1 000 | 0.5475 | **0.5385** | 1.017× | 0.5615 | 0.975× |
| `churn` | 10 000 | 5.5970 | **5.5705** | 1.005× | 5.9170 | **0.946×** |

**The two rungs tie on every read path and diverge on every write path, and
that is the whole judgement.** On `toggle` and `retype` the map and the
search are inside each other's noise in both directions at both sizes — an
`O(1)` hash lookup and an `O(log N)` search over 13 probes are the same
measurement once a commit costs half a millisecond. On `churn` the map is
**5.4% slower than doing nothing at all** at 10 000 rows and 2.5% slower at
1 000, because every removal shifts every later position and a position map
has to be rebuilt for it. That is the invalidation matrix, priced in
milliseconds instead of in review effort: it does not merely cost seven
maintenance sites to write, it costs time on the workload it exists to serve.
ADR-0085's 1.5×-against-seven-sites is superseded by this table and should
not be quoted again.

The search's own numbers are modest and the reason is worth stating rather
than dressing up: after ADR-0085‥0088 a commit's remaining cost is
`storageSet`, the `join`, and two or three earned walks, so removing an
unearned walk buys 3–7%, not a multiple. What it also buys is the *slope* —
the resolution stops growing with the region — and one fewer traversal of a
data structure the commit had no reason to traverse. `retype` is where the
share is largest (1.067× at 10 000) exactly as predicted: ADR-0084 keeps a
keystroke out of every predicate scan, so before this ADR the key walk was
one of that commit's only two walks and now it is neither.


## Decision

**A region's row table is ordered by key, and a dispatching key resolves to
its position by binary search over that order.**

> Every row a region owns enters its table through one of two `push` sites,
> both of which take the region's `nextKey` counter and then increment it; no
> emission ever assigns a row's key slot afterwards; and every removal — the
> sealed `remove` action, an ADR-0053 guard hit, an ADR-0050 predicate
> removal — preserves the relative order of the rows it keeps. Therefore a
> row table is **strictly ascending in `row[0]`** at every point a
> transaction can observe it, and that is a property of the emission, not a
> structure any site maintains. A dispatching key is resolved against it by
> one module-level `$lrx_row_seek(rows, key)` helper — half-open window,
> floored midpoint, position or `-1` — shared by every region and every
> dispatch branch of the module. **No region record slot holds an index and
> no site invalidates one.** A row leaves its table by `splice` at the
> resolved position; a guard hit splices at the position its own stage
> already resolved rather than searching a second time.

Three things the rule deliberately does *not* say.

**It does not say `removeIf` gets a search.** An ADR-0050 predicate removal
evaluates a predicate against every row; its walk is `O(N)` by contract, the
same way the shared pass and the write-back are, and it keeps its
kept-filter rebuild unchanged. Only the two *single-key* removal paths move.

**It does not say the search may assume anything about keys beyond the
order.** It compares with `<` and `===` on values that are always JavaScript
numbers from one counter, so ADR-0027's non-transitivity caveat cannot
arise here; if some future ADR lets a caller supply row keys, this ADR is
what it has to reopen.

**It does not put the helper in the host.** `$lrx_row_seek` is *generated*,
one per module, emitted exactly when some region declares a row event. That
is what keeps `runtimeAbi` at **17**: a new export in `leanrx_region.mjs`
would have bumped it to 18 and moved every backend's manifest, including the
hand-written js-framework-benchmark's, for a function that needs nothing
from the host. One helper rather than one search per branch is also the
difference between a module that grows and one that does not — inlining the
search into each of Toggle Lab's six row branches cost +1848 bytes; folding
it into a shared function saves 692.

### Region record slots and the ABI

**No slot is added, so the slot convention is unchanged**: `[handle, items,
nextKey, dirty, pending]`, then the two ADR-0050 count slots for a region
with counts, then the ADR-0051 container slot for a filtered region, then the
ADR-0075 child inventory. Mix Lab's nine-slot `crew` beside its eight-slot
`pins` stands for the fifth ADR running. **`runtimeAbi` stays 17**: no host
export, no host callback, no manifest field moves, and every generated
`.manifest.json` in the repository is byte-identical.

### The one new thing: `while` in the emitter

The JavaScript AST gains a single statement constructor, `Stmt.whileLoop`,
because a binary search cannot be written with `forOf` and the printer models
no other loop. It binds nothing of its own — its condition is checked against
the names already in scope and its body is an ordinary block — so the module
validator's `LRX-BE-018` unbound-name rule covers it exactly as it covers an
`ifThen`. The emitter uses it in exactly one place. The midpoint is floored
with `(span - span % 2) / 2` rather than `>> 1`: no bitwise operator exists in
the AST, and the arithmetic form is exact at every array length JavaScript
can represent rather than up to 2³¹.

### Witness

Toggle Lab's gate walks the invalidation matrix column by column on three to
four rows, not ten thousand. The row table's order is observable without
reaching into the closure: the reconcile renders rows in table order and
ADR-0047's `setKey` stamps each root with its key, so the DOM row list *is*
the table's key sequence. Nine cells — hydrate, append, the `updateAt` drain,
the ✕ splice, **append after a removal**, the guard-hit splice, a broadcast,
**a filter sweep in the same commit as a drain**, and `removeIf` — each
assert the sequence is strictly ascending and distinct, and most of them then
dispatch on *every* surviving row and demand that exactly that row moved: a
search that resolved a neighbour flips the wrong class, one that resolved
`-1` flips nothing. The two cells the round was told to insist on are the two
where a maintained index would have had to do work and an order does not —
the key after a removal is above every survivor because the counter never
rewinds over the hole, and the sweep that hides a row runs in the commit that
drained it and moves no key. The run ends by reading the persisted string
back, so the order the search relied on is the order the write-back saw.

The ADR-0088 walk counter is the other witness and it moves in the expected
direction on the expected commits: a `toggle` walks **3** where it walked 4,
a `retype` **1** where it walked 2 (the write-back alone), a `dblclick` **2**,
and a ✕ **4** where it walked 5. An append (3), a broadcast (4), a filter
click (1) and `clearCompleted` (1) are unchanged — none of them resolves a
key.

Both gates were checked against deliberately broken emissions rather than
assumed to bite: shrinking the search window from the wrong end fails the
first cell with "row 0 did not move", splicing at `drop + 1` fails the
removal cell's key sequence, and restoring a linear walk to the `toggle`
branch fails the ADR-0088 count at 4 against 3.

## Consequences

- Five generated modules change and the sizes barely move: Toggle Lab
  169 042 → 168 350 bytes (**−0.4%**, six inline scans replaced by six calls
  and one helper), Mix Lab 94 543 → 94 774 (+0.2%), Twin Lab 124 827 →
  124 935 (+0.1%), Branch Lab 10 062 → 10 105 (+0.4%), Nest Lab 12 427 →
  12 470 (+0.3%). Every other generated file in every bundle is
  byte-identical: every `.graph.json`, every `.manifest.json` — `graphHash`
  included — and the js-framework-benchmark bundle, which is a hand-written
  backend that carries no region record at all.
- The benchmark size gate and BENCHMARK.md stand unre-measured, for the same
  reason: the component backend and the benchmark backend are separate
  emitters and only the former changed.
- No host change and no validator change: `runtimeAbi` stays 17.
- ADR-0084 OQ2, ADR-0085 OQ2, ADR-0086 OQ3, ADR-0087 OQ3 and ADR-0088 OQ1 are
  **closed**. The `O(N)` walk they each named is gone; the key→index map they
  each declined is declined once more, this time on a measurement of its own
  rather than a price quoted from ADR-0085.
- ADR-0085's and ADR-0086's "a removal rebuilds the row array around
  unchanged tuples, so every survivor's cache cell stays valid" is superseded
  in its mechanism and unchanged in its conclusion: a `splice` moves the same
  tuples the rebuild moved, writes no field, and stales no cell.

## Open questions

1. **The order invariant is enforced by review and by witness, not by the
   type system.** Nothing in Lean stops a future emission from pushing a row
   at a position, sorting a table, or exposing `swapAt` to the component
   backend, and any of those silently breaks every search. What exists
   instead is the browser gate below — nine cells, each asserting the DOM's
   key sequence is strictly ascending *and* that a dispatch on every
   surviving row resolves to that row — and this ADR's decision paragraph,
   which such a change would have to reopen by name. A structural check over
   the emitted AST (no assignment to a row's slot 0; no `push` onto a rows
   slot whose head is not `regions[r][2]`) is possible and was not written:
   it would restate the enumeration above in a second place, and the round
   judged the witness the more honest of the two.
2. **`storageSet` and the `join` are the floor, at 35% each** (ADR-0087 OQ1,
   ADR-0088 OQ2, unmoved). Neither narrows under identity keying and the
   per-commit visibility contract.
3. **A shared predicate pass is per commit, so it is not a cache**
   (ADR-0088 OQ3, unmoved).
