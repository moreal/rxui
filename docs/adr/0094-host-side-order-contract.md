# ADR-0094: The host does not disturb the array it is handed

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0093 audits every module the component backend emits for the shapes that
could break a region's row table, and it wrote down where it stops:

> **The host is still review-checked.** R1 lets a table reach
> `createKeyedRegion`'s handle and `$lrx_row_seek`, and the audit stops at the
> call. […] Nothing checks *that* the host does not reorder, and the cheapest
> thing that would is a rule over the host source rather than over the
> emission — a different layer with a different gate.

The gap is not hypothetical. What the component backend emits, in every
dispatch function of every region-carrying module, is

```js
regions[0][0]["update"](regions[0][1], null);
regions[0][0]["updateAt"](pending_row, regions[0][1][pending_row], null);
const scan = $lrx_row_seek(regions[0][1], key);
```

— the row table itself, then one of its rows, then the table again. And what
`runtime/leanrx_region.mjs` holds on the far side of those calls is a `splice`,
a two-slot exchange, and a positional removal:

```js
current.splice(index, 1);          // removeAt
current[first] = high;             // swapAt
previous[kept] = entry;            // update
```

Every one of those is the correct thing to do to the host's *own* entry array
and a catastrophe on the *caller's* table: ADR-0092's `$lrx_row_seek` is a
binary search, exact only while the table is strictly ascending in `row[0]`, so
a single misplaced `items.splice` turns every subsequent dispatch into a silent
lookup of the wrong row. In the source the two are the same shape. `current`
and `items` are both identifiers holding arrays; only what each is bound to
says which one the statement disturbed, and that is a question no rule over the
host's text answers.

There are two kinds of caller and both are exposed. The component backend hands
over `regions[r][1]` and depends on the order; the hand-written
js-framework-benchmark hands its own array to `swapAt(first, second, items, …)`
and drives `removeAt`, splicing around both.

## Decision

**Pay.** The layer is a **contract test at the region-runtime gate**: every
array a caller hands a region host crosses the boundary as a frozen copy and is
re-verified after every later call, and the whole existing 1 100-line region
suite runs behind that guard. `Test/js/region_contract.mjs` holds it,
`scripts/check_region_runtime.sh` runs it, and it reports under one new code,
`LRX-HOST-001`.

Four rules.

* **H1 — the array crosses frozen.** A caller's array is handed to the host as
  `Object.freeze(source.slice())`, so a `push`, `splice`, `sort`, `reverse`, or
  element assignment throws a `TypeError` *inside the host call*. The frozen
  copy stays registered for the life of the process and its length and element
  identities are re-verified after every later call, so a host that stashes the
  array it was given and disturbs it three calls later is caught at that later
  call rather than never.
* **H2 — the key slot is snapshotted.** `row[0]` of every row a host is handed,
  whether inside a table or alone at `updateAt`, is recorded and re-checked
  after every later call.
* **H3 — the handle surface is closed.** The guard knows the exact export list
  of each host and which of each method's arguments are caller arrays. A method
  it cannot classify — and a method it classifies that the handle no longer
  exports — fails on the spot.
* **H4 — the surface must actually be exercised.** Every array-taking entry
  point of every region host has to be reached at least once under the guard,
  and at least one array has to have been intercepted, or the gate fails. A
  guard that has been neutered cannot pass quietly.

### Which layer, and why not the other two

**A rule over the host source** was the option ADR-0093 named, and it is the
one that cannot work. The question is semantic: `current.splice(index, 1)` and
`items.splice(index, 1)` are the same text, and a rule that hard-codes the
parameter names is defeated by a rename. Answering it statically needs an AST
and a binding analysis for JavaScript — the emitter has a Lean AST because it
*builds* one, and `runtime/*.mjs` is hand-written text with no such handle. A
regex over the host would be the second checker in a vocabulary the repo cannot
parse, which is exactly the "not checkable" ground on which ADR-0093 declined
narrowing the emission helpers. Freezing answers the same question by running
it: the freeze follows the reference wherever it travels and whatever it is
renamed to, into a field the host stashed, into a helper it forwards to.

**An ABI sentence plus a version bump** is what is already there, and ADR-0093
OQ1 is the record of it not being enough. A bump says *the host changed*; it
does not say the change kept the order. Reading a bump is the review this ADR
exists to replace. The sentence is still worth writing — the dynamic-region
internals doc now carries it — but as documentation of a checked fact, not as
the check.

### Why a running gate suffices here and did not in ADR-0093

ADR-0093 rejected the nine-cell browser gate as the *primary* check with an
argument that looks like it should apply to this one: what a running witness
witnesses is the cases somebody wrote, and the emission that breaks the order
is the emission nobody wrote a cell for. The two situations differ in one
respect that decides it.

The emission surface is **open**: a new emission path appears whenever the
backend learns an action, with no ceremony that would force anyone to notice.
The host surface is **closed**, and closed for a reason the repo already
enforces — a new host export changes what generated modules import, so it moves
`runtimeAbi` and takes an ADR with it (`docs/guides/architecture.md`: "an
ABI/ADR update when a host contract changes"). H3 nails the guard to that
event: the surface list is spelled out, so a new export fails the gate until
somebody declares which of its arguments are caller arrays. A contract over the
six array-taking entry points of the three hosts is therefore not a sample of
the surface. It is the surface.

### Three notes on the edges

**The guard hands over a copy, not the caller's own array.** Both caller shapes
reuse their array across calls — the component backend pushes onto
`regions[r][1]` between transactions, the benchmark splices its own rows around
`swapAt` — so freezing the original would break the callers rather than test
the host. The stand-in preserves length, order, and every row object's
identity, which is everything the host's entry cache and the mount/update
callbacks can see; no region host distinguishes the array object itself, and H3
is what keeps it that way. The cost is stated plainly: the contract proves the
host does not disturb *the array it is handed*, and the array it is handed in
this gate is an identical stand-in.

**Rows cross unfrozen, deliberately.** A host forwards each row to generated
callbacks that own its other slots — the ADR-0085 serialization cache and the
ADR-0086 display cache live on the row tuple — so freezing rows would pin a
contract the composite violates in production while the gate stayed green on
its own callbacks. Only slot 0 is the order's business, and H2 covers slot 0 by
snapshot instead.

**The one bypass a freeze does not throw on is banned in source.**
`Reflect.set` and `Reflect.defineProperty` fail *silently* on a frozen array:
the mutation would not happen in the gate but would happen in production, where
nothing is frozen. That is the single hole in H1 and it is closed by one regex
in `check_region_runtime.sh`, beside the `new Proxy` / `eval(` / `innerHTML`
ban that was already there. It is a source rule, and it is affordable precisely
because it is a ban on names rather than an analysis of bindings.

### The diagnostic

**`LRX-HOST-001`, one code, raised by the region-runtime gate**, with the rule
tag, the host, and the method as the message's subject:

```
LRX-HOST-001 host order contract (H2) at keyed.updateAt:
  the row it was handed changed its key from 2 to "2"
```

One code rather than four, for ADR-0093's reason: the reader who trips it needs
to know which shape they wrote and where, and the rule tag carries that; no
caller branches on which. H1's ordinary failure mode is not `LRX-HOST-001` at
all but a `TypeError` thrown at the offending line of the host, which is a
better localization than any message this gate could print; the sweep's
`LRX-HOST-001 (H1)` covers what does not throw.

### Cost

**Layer**: a test, not the compiler and not the runtime. **Subject**: the three
region hosts in `runtime/`. **Price**: `node Test/js/region_runtime.mjs` goes
from 0.116 s to 0.415 s — 1 401 arrays guarded across the six array-taking
entry points, 1 967 sweeps, the two fuzz loops dominating both counts — inside
a gate that is one of twenty in `scripts/check.sh`. **Zero output bytes and no
ABI move**: no file under `runtime/` changes, so every generated module and
every bundled host file is byte-identical and `runtimeAbi` stays **17**.

### Witness

The wiring is three lines: `Test/js/region_runtime.mjs` imports each host under
a private name and rebinds the public name to a guarded constructor, so all
fifteen region constructions and every call in the file — including the
400-round placement fuzz and the 600-round monotone-key fuzz over numbers,
bigints, strings, symbols, objects and mixed types — run against the real host
behind the contract.

One new case plays the **two caller shapes** end to end. The component-backend
shape builds its table with a monotone counter, `update`s it, drains one row
through `updateAt`, performs the ADR-0092 sealed single-row `splice`, appends
past the hole, and after each host call asserts the table is still strictly
ascending in slot 0 *and* that a binary search spelled exactly like the
generated `$lrx_row_seek` resolves every key to its own position. The benchmark
shape hands a target order to `swapAt`, checks the two-move cost, drives
`removeAt`, and splices its own array around both.

Both directions were checked against deliberate breakage.

- *The host, broken six ways.* `update` reversing the table it was handed, and
  `swapAt` exchanging two of its rows, each throw `TypeError: Cannot assign to
  read only property '0'`. `update` stashing the table so a later `removeAt`
  splices it throws `Cannot delete property '0'` — at the later call, which is
  the aliasing escape H1 exists for. `update` replacing a row with an
  equal-keyed copy after it is otherwise done — a mutation no other assertion
  in the suite can see — is caught by H1's identity sweep. `updateAt` re-keying
  its row is caught by H2. A handle that grows a `sortByKey` export is caught
  by H3.
- *The guard, broken twice.* Deleting H1 — the freeze and the length/identity
  sweep — makes the equal-keyed replacement pass, so H1 is the only thing that
  was catching it. Neutering `guardHost` to hand back the raw handle does not
  pass quietly: H4 fails naming all six unexercised entry points. The vacuity
  failure mode of a wrapper is that it wraps nothing, and that is the mode H4
  is for.

## Consequences

- **Every generated file in every bundle is byte-identical**, for the plain
  reason that nothing under `runtime/` or `LeanRx/` changed: the diff is
  `Test/js/region_contract.mjs` (new), `Test/js/region_runtime.mjs`,
  `scripts/check_region_runtime.sh`, and documentation. The bundled host files
  — `leanrx_region.mjs`, `leanrx_unkeyed_region.mjs`, `leanrx_delta_region.mjs`
  — are copied from `runtime/` verbatim by the CLI, so the codegen gate's
  double-generate `diff -ru` and each artifact test's manifest assertions pin
  that claim on every generator run. The benchmark size gate, its manifest and
  BENCHMARK.md stand untouched.
- **No host change and no ABI move**: `runtimeAbi` stays **17**.
- **ADR-0093 OQ1 is closed for `createKeyedRegion`'s handle.** Its replacement
  is narrower and stated below: the generated key search, where the table stops
  being spelled `regions[r][1]`.
- The unkeyed and delta hosts are covered by the same guard even though
  ADR-0092's search does not depend on them, because the rule "do not disturb
  the array you were handed" is the same rule and the marginal cost was one
  line each.

## Open questions

1. **`$lrx_row_seek`'s body is checked by neither side.** ADR-0093's R1 lets a
   row table cross into the generated search, and inside that function the
   table is a parameter named `rows` — not spelled `regions[r][1]`, so R1 does
   not reach it, and not a host export, so this contract does not either. R4's
   parameter half forbids `rows[i][0] = …`, but a `rows.sort()` or
   `rows.splice(…)` in the helper passes both — verified, not read: injecting
   `rows["sort"]()` as the helper's first statement and rebuilding, Toggle Lab
   emits with the sort in its bundle and `lake exe leanrx_toggle_js` exits
   zero. The helper is emitted by one Lean function and reads only today;
   closing the hole properly means giving the audit a notion of *which
   parameters carry a row table*, which is an interprocedural step neither ADR
   needed so far.
2. **The contract is over a stand-in, by construction.** H3 is what keeps a
   host from being able to tell the stand-in from the original; a host that
   ever keyed behaviour on the array object's identity (a `WeakMap` from table
   to state, say) would satisfy this gate and fail in production. Nothing
   proposes such a host, and the note is here so a round that does has to
   reopen the copy.
3. **`storageSet` and the `join` are the floor, at 35% each** (ADR-0087 OQ1,
   ADR-0092 OQ2, ADR-0093 OQ2, unmoved).
4. **A shared predicate pass is per commit, so it is not a cache**
   (ADR-0088 OQ3, ADR-0093 OQ3, unmoved).
