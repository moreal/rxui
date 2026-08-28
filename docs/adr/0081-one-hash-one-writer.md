# ADR-0081: One hash, one writer — the route cap is the contract

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0080 made the routed field's sealed literal set the union of every
filter table over it, and closed by observing that all the *remaining*
route caps "are properties of the route table itself". One of them was
never examined: `validateRoutes` opens with `spec.routes.size ≤ 1`, and
nothing said whether that is a principled limit or a leftover from the
one-route scaffolding ADR-0063 shipped. Every other piece of the route
emission is already indexed by `routeIndex` — `$lrx_route_{i}_arm_{j}`,
`$lrx_route_{i}`, `route_hash_{i}`, `route_off_{i}` — which reads exactly
like a cap that outlived its reason.

The survey lifted the guard, compiled a two-route component, and ran it.

**Two routes generate cleanly.** Nothing in the backend needs a change.
Two seed folds, two dispatch functions, two `listenHash` registrations,
two write blocks, each indexed and each naming its own field's slot:

```js
  const route_hash_0 = readHash();
  state[0] = route_hash_0 === "#/" ? "all" : route_hash_0 === "#/on" ? "on" : state[0];
  const route_hash_1 = readHash();
  state[1] = route_hash_1 === "#/" ? "all" : route_hash_1 === "#/hot" ? "hot" : state[1];
```

**Mount is not where they collide.** The two seeds write distinct state
slots and fall back to their own field's declared initial, so they are
order-independent: mounting at `#/hot` seeds `tone` and leaves `mode` at
its initial. (Two routes over the *same* field would make the later seed
win, but that is the only order-dependence at mount, and it is subsumed by
everything below.)

**The write blocks race for one string.** Both blocks sit in the commit
prologue behind their own field's changed bit:

```js
    if (changed[0]) { …; writeHash("#/on"); …; }
    if (changed[1]) { …; writeHash("#/hot"); …; }
```

One transaction that writes both fields opens both blocks, and the *last*
`writeHash` wins. The URL then encodes route 1's field and silently
misrepresents route 0's.

**One `hashchange` wakes both dispatches — and the second reads the hash
the first just wrote.** `listenHash` reads `location.hash` at dispatch
time, and dispatch 0's commit assigns the hash *synchronously*, so within
one event dispatch 1 no longer sees the hash the event announced. What
makes this data loss rather than a harmless no-op is the ADR-0063
fallback: a route table is a **total** function from the hash space, so a
hash it does not name falls to its declared-default arm. Each route claims
the whole hash space; anything the other route writes is "unknown" to it
and resets its field.

The cascade, observed in Chromium on the generated module — mounted at
`#/`, one click on a button whose event is `set mode "on" then set tone
"hot"`:

```
event:both → route:mode:write ("#/on") → route:tone:write ("#/hot")   [commit 1]
hashchange "#/hot" → route 0 unknown → mode := "all" → writeHash("#/") [commit 2]
                   → route 1 reads "#/" → tone := "all"                [commit 3]
hashchange "#/"    → both equal-value, two empty commits               [commit 4,5]
… 7 commits, both fields back at their declared defaults, URL back at "#/"
```

Separately, the four `LRX-TYPE-117` branches with compile-fail witnesses
(`RouteArmShape`, `RouteHashShape`, `RouteDefaultUnmapped`,
`RouteLiteralOutsideFilterUnion`) were the minority: the cap, a derived
target, an unfiltered target, an empty arm table, a duplicate hash literal,
and a duplicate state literal all rejected without anything pinning them.

## Decision

**The cap stays, and it is restated as a contract about `location.hash`
rather than about the route table: one hash, one writer. Every reachable
`LRX-TYPE-117` branch gets its own witness, pinned on its message rather
than the shared code.**

`location.hash` is one string with one writer, and a route table is a
total function from that string onto one field's literals. Two tables are
therefore two total functions over one string, and no ordering rule
rescues them: whichever block writes last defines the string, and the
other route reads that string as a hash it does not name and resets its
field to the declared default. This is not a scheduling accident that a
"last writer wins, deterministically" rule could tame — the loser's state
is destroyed either way.

The two shapes a future lift would have to take, recorded so the next
reader does not re-derive them:

1. **Disjoint hash sub-namespaces with partial tables.** Each route owns a
   prefix and *ignores* hashes outside it. That replaces the total-function
   fallback — the thing that makes "exactly one arm maps the declared
   default" a rule at all — with a partial one, so every existing route's
   unknown-hash contract changes.
2. **One table over the tuple of routed fields.** `route (a, b) := when
   "#/on/hot" ("on", "hot") then …` is a single total function again, which
   is to say the cap with a wider field. This is the shape that preserves
   the current contract, and it is a strictly additive future item.

Neither is needed by anything today, so the cap is kept as-is and its
diagnostic now names *both* route declarations, the way ADR-0080's union
diagnostic names both filter tables.

**Witnesses.** Five new compile-fail fixtures — `RouteTwice`,
`RouteDerivedField`, `RouteUnfilteredField`, `RouteDuplicateHash`,
`RouteDuplicateLiteral` — each matched on its own message, so the branches
cannot collapse into one another behind the shared `LRX-TYPE-117` code.
The remaining two branches are not fixture-shaped:

- `route item declares no arm` is unwritable in the surface DSL, because
  the item grammar is `sepBy1(term, " then ")`. It has the same standing as
  the three sibling "declares no arm" guards (`LRX-TYPE-113`,
  `LRX-TYPE-115`), so it is witnessed the way the key-arm one is: a
  hand-built `ComponentSpec` in `Test/Component/Model.lean`.
- `route item targets a field without a declared String initial` is
  **dead**. `RouteSpec.field : Field Γ String` fixes the schema position's
  type, `validateValues` forces the value at that position to name the same
  field, and `ScalarLiteral String` has exactly one constructor — so a
  source at the routed index always carries a `.string` initial, and a
  non-source is already rejected by the derived-target branch above it. It
  is retained as the total-function fallback of the `match`; there is no
  witness to write, which is why this ADR says so instead.

**ADR-0080 OQ1 — a persisted region under a route — is closed in Twin
Lab.** `persist right := "leanrx-twin-lab.right"` persists *one* of the
two regions the routed field drives. The two write paths are guarded on
different things by construction and the emission is the proof: the
persistence sweep is `if (region_touched_1)` with no `changed[1]` disjunct,
while the hash write is `if (changed[1])` in the commit prologue, ahead of
every region block. Persistence adds no region-record slot, so `right`'s
record is byte-for-byte the six slots with the container at 5 that ADR-0079
and ADR-0080 pinned, and `left`'s eight-slot record with the container at 7
is untouched.

## Consequences

- The route contract now reads as two independent claims: the *table*
  rules are properties of the route item (ADR-0063/0080), and the *count*
  rule is a property of the browser's one-slot hash. A reader who wonders
  why the emission is indexed by route when only one is legal finds the
  answer, and the trace, in this ADR.
- Every `LRX-TYPE-117` branch is now accounted for: six witnessed by
  fixture, one by spec-level test, one documented dead. The compile-fail
  harness pins the cap's diagnostic at both route spans, so a future
  refactor that drops one span fails loudly.
- Twin Lab's browser gate measures the ADR-0080 OQ1 independence in both
  directions: a `mode` flip runs both twin sweeps, writes the hash once,
  and emits no `storage:right:write`, leaving the stored string byte-equal;
  a `right` row toggle emits exactly one `storage:right:write` carrying the
  drained row and no `route:mode:write`, leaving the URL where the flip put
  it. A third test hydrates `right` from storage while the hash seeds
  `mode` to the union-only literal, and the one hydrate commit's own sweep
  applies that literal to the rows it just mounted — one commit, no hash
  write, and the two unpersisted regions mount empty though one of them
  shares the routed field.
- No host change and no validator change: `runtimeAbi` stays 17, and the
  only generated artifact that moves is Twin Lab's, which gains the
  `persistence` feature, one hydrate function, and one persistence sweep.

## Open questions

1. **A tuple route.** Shape 2 above — one total table over several routed
   fields — is the additive way to route more than one field. Nothing
   needs it yet, and the arm syntax (`when "#/on/hot" ("on", "hot")`) would
   be the first route arm whose right-hand side is not a single literal.
2. **A row write that provably cannot change a selection.** Carried over
   from ADR-0080: the drain sets the touched flag, so the sweep runs even
   when the written field is not the filter's subject. Whether narrowing
   that is worth the analysis is still unexamined.
