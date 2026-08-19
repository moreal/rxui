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
| 6 | DOM text writes |
| 7 | stable trace-event strings |

Counters are cumulative for that mount and start at zero after initial mount.
Mutating the returned array or its trace copy cannot modify transaction control.
Trace events use declared source, derived, sink, and event names. They are a
development observability contract, not a timing API.

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
