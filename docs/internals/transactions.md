# Transaction, propagation, and instrumentation contract

Generated M5 event handlers execute against one mount-local transaction context.
The outermost handler snapshots source values, nested synchronous dispatch shares
that context, and only depth zero commits. Update evaluation can write a source
multiple times; the changed-source frontier compares the final value with the
snapshot using the sealed lawful scalar equality plan.

Commit has two ordered phases. Derived nodes are visited in the certified graph
schedule and evaluate only when a direct dependency changed. Equality stops the
frontier at an unchanged derived value. After all derived work completes, text
sinks whose direct dependencies changed evaluate against the final store. A
mount-local sink cache suppresses an unchanged text value before `setText`.
The DOM host only installs listeners and writes nodes; it does not discover
dependencies, build the frontier, or schedule work.

Each disposer exposes `disposer.instrumentation()`, which returns a copied
development snapshot:

| Index | Meaning |
|---:|---|
| 0 | current nested transaction depth |
| 1 | outer commits |
| 2 | source writes evaluated |
| 3 | derived evaluations |
| 4 | changed derived values |
| 5 | sink evaluations |
| 6 | DOM writes (text, property, or dynamic attribute) |
| 7 | stable trace-event strings |

Counters are cumulative for that mount and start at zero after initial mount.
Mutating the returned array or its trace copy cannot modify transaction control.
Trace events use declared source, derived, sink, and event names. They are a
development observability contract, not a timing API.

Dynamic-region emitters count every compiler-emitted `setText`, `setProperty`,
and `setAttribute` call in index 6. Region insertion, removal, reorder, and
branch replacement are structural operations reported separately by
`regionInstrumentation()`; they are not silently folded into the DOM-write
counter. Todo currently uses reference-style propagation after each action, so
its manifest says `reference-propagation` rather than `actual-change`.

Specialized form emitters preserve the same indices. Parser/validator execution
is event-local update work, not a graph-derived node, so it never increments
indices 3 or 4 when the manifest reports `derivedCount: 0`. Index 2 includes
every evaluated source write, including Temperature's explicit active-scale and
successful conversion writes. Index 5 increments before each affected sink
evaluation; submit revalidation intentionally evaluates every validation sink,
while cache equality controls only index 6. Trace entries contain stable declared
event/payload/sink names and never retain raw key payloads.

Ordinary event expressions may read sources. A direct derived read fails with
`LRX-TYPE-108` and explains that a transaction barrier is required. LeanRx does
not return a stale cache; an explicit `readDerived` barrier remains future work.

The homogeneous abstract semantics model nested events as a list of source-write
transactions. Lean proves their sequential source-store application equals the
flattened write list and specializes the existing optimized/reference observation
equivalence to that list. The pure theorem does not model event-expression
evaluation or commit counts; the single outer commit is executable/browser
evidence. This theorem covers the pure static-DAG model.
Generated JavaScript, the context-array representation, DOM, and browser remain
inside the documented trusted computing base and are checked differentially and
in Chromium rather than formally verified.
