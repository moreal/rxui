# ADR-0063: The freeze boundary — routing and persistence host exports

- Status: Accepted
- Date: 2026-08-28

## Context

The lexicon-invariant round left Toggle Lab's TodoMVC interaction parity
with exactly two gaps — URL routing (`#/active` sync) and localStorage
persistence — and both need host exports, which the performance freeze
has treated as suspect since it began. This round is a decision, not an
execution: weigh the freeze-compatible residue against the exports, pick
one axis, and record the other's disposition.

The residue was surveyed first. The single-field-literal equality
comparison — one projected row field against one string literal — is
spelled five ways in the model (`RowClassSelect.field/equals` for
ADR-0044, `RowReflect`'s `RowExpr` + `checkedIf` literal for ADR-0049,
`regionRemoveIf`'s positional args and the anonymous
`Option (Nat × String)` predicate for ADR-0050, `RegionFilter.arms`'
triple slot for ADR-0051, `RowGuard`'s `RowExpr` + literal for
ADR-0053), lowered by seven backend sites that each rebuild the same
`.binary .eq (.index … (uint (field + 1))) (.literal (.string lit))`
subtree, resolved by six longhand `fields.idxOf?` elaborator sequences,
and bounds-checked by nineteen near-identical validator blocks under
five error codes. The only pre-existing sharing is the anonymous pair
reused by the count/hidden/checked subjects — and even there the backend
duplicates the scan loop and the validator duplicates the bounds rule
(`LRX-VIEW-038`/`LRX-VIEW-042`) word for word.

The freeze's actual boundary was surveyed second. The size gate
(`check_js_framework_benchmark.sh` →
`measure_js_framework_benchmark_size.mjs`) is a strict byte-identity
check over exactly `index.html` and `main.mjs`; the manifest is not a
measured asset, and `main.mjs` contains no ABI number anywhere — the
runtime ABI is a manifest fact, checked only by test scripts. The
flattener inlines the hosts and the compactor prunes every unreachable
top-level function declaration *before* identifier renaming
(`JsCompact.lean`), so a host export the benchmark never names cannot
reach the emitted bytes. ADR-0048 already crossed this line under the
freeze: `focus(node)` shipped as ABI 16 with the benchmark module
byte-identical and only its manifest's ABI number changing.

## Decision

**Take the parity axis: adopt routing and persistence as the next
round's work — one runtime ABI 17 bump adding five sealed DOM-host
exports under the ADR-0048 pruning condition — and defer the
freeze-compatible residue. This round ships the decision only; no code
changes.**

The deliberation, per option:

1. **Field-predicate unification — deferred, not rejected.** A named
   `FieldPredicate` (a `RowExpr` subject plus the compared literal, so
   the ADR-0049 reflect and the ADR-0053/0054 trimmed guards join
   without regression) with one shared comparison-expression builder is
   byte-neutral by construction: `rowExprJs (.field i)` produces exactly
   the subtree the seven sites hand-build, and the printer is a pure
   function of the AST. But the safe scope ends at the comparison
   expression — sharing the surrounding scan loops would perturb the
   per-feature ident prefixes (`count_scan_*`, `hidden_row_*`,
   `kept_*`, `row_guard`) that the golden artifacts assert verbatim —
   and no gate demands the consolidation, while the parity gaps demand
   the exports. The unification is recorded here as a later hygiene
   round with its byte-neutral scope fixed in advance.
2. **Attribute-position count labels (ADR-0062 open question 1) —
   re-rejected.** TodoMVC's label is a text position; no lab or parity
   target consumes a count-driven attribute string, and speculative
   vocabulary is what every ADR since 0043 has declined.
3. **Affordance-contract agreement checking (ADR-0059 open question 1)
   — deferred.** Every shipped affordance agrees with its dispatch by
   construction and no divergence has ever been observed; a checker rule
   needs a contract inventory the model does not carry, and building one
   for zero observed bugs is not this round's work.
4. **The exports — adopted.** The remaining parity is unreachable any
   other way, and the survey shows the freeze survives the bump: the
   freeze pins the measured bytes and the BENCHMARK.md numbers, not the
   host surface.

### Export surface draft (executes next round)

Five exports in `runtime/leanrx_dom.mjs`, plain `export function`
declarations in the existing host style:

- `readHash()` — returns `location.hash`; called once at mount to seed
  the routed state field.
- `listenHash(handler)` — `window.addEventListener("hashchange", …)`
  returning a removal closure. This is the first listener whose lifetime
  is not rooted in the mounted subtree, so its disposer joins the
  `listenerDisposers` array handed to `makeDisposer` explicitly.
- `writeHash(value)` — assigns `location.hash`; generated code writes
  flip-only against a cache slot, and an equal-value assignment fires no
  `hashchange`, so no echo loop exists.
- `storageGet(key)` / `storageSet(key, value)` — synchronous
  `localStorage` reads/writes of one string. The effects-host adapter
  route (`leanrx_effects.mjs`, the Notes precedent) is rejected for
  this: the generic component backend has no effects import path, and
  grafting one on would be a second ABI surface for the same two calls;
  serialization stays in generated code so the host stays dumb.

### Sealing

- **Routing seals onto the routed state field** — the one component
  state field that already carries the ADR-0045 filter selection and
  the ADR-0051 filter table. A sealed route item maps the sealed hash
  literal set (`#/`, `#/active`, `#/completed`-shaped) one-to-one onto
  the field's existing state literals: mount seeds the field through
  `readHash` (unknown or empty hash falls to the declared default),
  `hashchange` dispatches the same set-field transaction the filter
  buttons dispatch (the whole commit path reused — selection, filter
  sweep, count labels), and `writeHash` rides the set-field commit.
- **Persistence seals onto the declared region row table** — mount
  hydrates through the existing append path from one `storageGet` (a
  missing or unparsable value mounts the region empty, the ADR-0050
  "empty by construction" reasoning), and one `storageSet` rides the
  region-touch sweep per region-touching transaction, the shared
  touched flag of ADR-0050/0051/0058. A filter change alone touches
  nothing and therefore persists nothing.

### Freeze conditions (the byte-identity contract for ABI 17)

1. Both vocabularies are reachability-gated in the import emission (the
   ADR-0048 arm shape): a component with no route/persist item emits a
   byte-identical module. The benchmark app declares neither, so the
   flattened text gains only unreachable function declarations, pruned
   before renaming — `main.mjs` byte-identical, size gate green, no
   benchmark re-run owed (regression watch only).
2. The new host code adds **no non-literal module-level binding**: only
   literal-initialized or uninitialized top-levels are prunable, so a
   `new Map()`-style module global would ship in the benchmark bundle
   forever and break the size baseline.
3. The new host code uses **no compactor-rejected construct** (`class`,
   `switch`, `await`, regex literals, destructuring, multiple
   declarators) — the rejection scan runs over the whole inlined host
   text before pruning — and pulls no helper from another host module
   (`inlineHost` throws on residual imports).

### ABI bump checklist (ABI 17, next round)

Per the bump convention, 24 mechanical literal sites:
`LeanRx/Core/Version.lean`; six Lean backend test assertions
(`Test/Backend/{Component,Grid,JsFrameworkBenchmark,Scalar,Tabs,Todo}.lean`);
sixteen JS artifact gates (fifteen `Test/js/*_artifacts.mjs` plus
`examples/expression_playground_js.mjs`); and `scripts/check_cli.sh`'s
doctor line — the one site missed during the ABI 16 fan-out and fixed a
round late, so it is named here explicitly. Beyond the literals: a new
"ABI 17 adds …" section in `docs/internals/runtime-representation.md`
(this round already repairs that document's stale "currently version
15" sentence found during the survey), the `RuntimeNames` additions and
conditional import arms in the component backend, `routing`/
`persistence` manifest features, real-DOM unit gates for each export
beside the other DOM-host helpers in `counter.spec.mjs`, compile-fail
fixtures for the sealed route/persist surfaces, and the Toggle Lab
browser gates pinning hash seed, hashchange dispatch, flip-only
`writeHash`, hydration, and per-touch persistence.

## Open questions

1. **Resolved by the ABI 17 execution round: the route surface.** The
   sealed item is `route field := when "#/hash" "literal" then …` in the
   component-command rewrite pattern (arm shape `LRX-ELAB-128`, table
   rules `LRX-TYPE-117`): distinct `#/`-shaped hash literals mapped
   one-to-one onto the routed field's existing state literals — the
   declared default plus the ADR-0051 filter table's literals, on a
   field that must carry a declared filter — with exactly one arm
   mapping the declared default, so the unknown-or-empty-hash fallback
   is a table entry rather than a separate path. Two shapes settled
   during execution: `listenHash` is `(state, context, dispatch)` in the
   `listen(...)` style because generated code has no closures to hand a
   bare handler, and the flip-only `writeHash` cache is the routed state
   slot itself — the commit sweep's `changed` flag is the flip, so no
   new context slot exists.
2. **Resolved by the ABI 17 execution round: the storage key policy.**
   The sealed item is `persist region := "storage-key"` — one sealed
   literal key per component (`LRX-ELAB-129`/`LRX-TYPE-118`), targeting
   one declared keyed region. Serialization is generated code's
   throw-free split/join escape (`%`→`%25` first, then `,`→`%2C` and
   `;`→`%3B`; fields behind the key slot joined by `,`, rows by `;`), so
   no decode step can throw; hydration of a missing or empty value
   mounts the region empty, and any row whose field count differs from
   the declared arity fails the whole value closed to the empty region.
   Hydration itself is one ordinary transaction whose writes push the
   parsed rows through the existing append path, so the shared commit
   sweep settles rows, counts, visibility, filter, and the normalized
   write-back together.
3. **The `FieldPredicate` unification stays open** with its byte-neutral
   scope recorded above: model and validator consolidation plus the
   shared comparison builder, scan loops excluded.
4. **The carried rejections stand.** Attribute-position count labels
   stay rejected; affordance-contract checking stays untouched; the
   two-threshold count grammar stays rejected (ADR-0062).

## Consequences and limitations

- This round changes documentation only, so every gate is green by
  construction and every lab and the benchmark bundle are trivially
  byte-identical; the freeze holds with nothing to verify.
- The next round pays one ABI bump and inherits the checklist above;
  after it, Toggle Lab's TodoMVC interaction parity has no known
  remaining gap.
- The dispatcher, `reconcile6`, the row vocabulary, and the host ABI
  are untouched this round; the key set stays sealed at Enter/Escape;
  the guard literal stays `""`; the count-label literal stays one; row
  guards stay single-field remove-or-commit; row scope still has no
  `s!`; branch cells stay single-level two-branch with exact
  click/dblclick agreement; and the parent-disposer instrumentation gap
  is unchanged.

## Confirmation

The decision round's claims were confirmed by inspection: the size
gate's asset list (`index.html` + `main.mjs` only), the absence of any
ABI byte in the checked-in benchmark `main.mjs`, the pruner's
prune-before-rename order in `JsCompact.lean`, the ADR-0048 precedent
record in DOGFOOD.md, and the grep-counted duplication figures in the
Context section.

The ABI 17 execution round then landed the scope exactly — five
exports, two sealed surfaces, three freeze conditions — and is
confirmed by execution: the size gate is green with the benchmark
`main.mjs` byte-identical (the five host functions are pruned before
renaming; only the manifest's `runtimeAbi` number changed), and every
other lab emits byte-identical JavaScript because both vocabularies are
reachability-gated in the import emission. The 24-literal fan-out
landed in one commit, `scripts/check_cli.sh`'s doctor line included
this time. The gates named in the checklist exist: real-DOM unit tests
for all five exports beside the other DOM-host helpers in
`counter.spec.mjs` (including the equal-value-hash no-echo pin), five
compile-fail fixtures for the sealed route/persist surfaces
(`LRX-ELAB-128`/`129`, `LRX-TYPE-117`/`118`), elaborator-shape
assertions in `Test/Elab/Component.lean`, generated-artifact pins in
`toggle_artifacts.mjs` (route seed, dispatch, flip-only write, persist
sweep, hydrate parse, explicit `route_off_0` in the disposer list), and
seven Toggle Lab browser gates covering the hash seed, the unknown-hash
default, hashchange dispatch through the shared set-field commit,
flip-only `writeHash` with the echo settled at one write, hydration
round-trip (separators and the escape character included), fail-closed
wrong-arity hydration with normalized overwrite, and
one-`storageSet`-per-region-touch with the filter change persisting
nothing.
