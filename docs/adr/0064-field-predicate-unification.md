# ADR-0064: The field-predicate unification — one sealed spelling for the single-field-literal equality

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0063 deferred the freeze-compatible residue with its byte-neutral
scope fixed in advance: the single-field-literal equality — one
projected row field compared against one string literal — was spelled
five ways in the model (`RowClassSelect.field/equals` for ADR-0044,
`RowReflect`'s `RowExpr` + `checkedIf` literal for ADR-0049,
`regionRemoveIf`'s positional args and the anonymous
`Option (Nat × String)` predicate for ADR-0050, `RegionFilter.arms`'
triple slot for ADR-0051, `RowGuard`'s `RowExpr` + literal for
ADR-0053), lowered by seven backend sites that each rebuilt the same
`.binary .eq (.index … (uint (field + 1))) (.literal (.string lit))`
subtree by hand, and bounds-checked by nineteen near-identical
validator blocks. This round executes exactly that recorded scope —
model and validator consolidation plus the shared comparison builder,
scan loops excluded — under the performance freeze: surface grammar,
error codes, validation message strings, manifests, and every emitted
byte are unchanged, and there is no ABI bump.

## Decision

**Introduce the named `FieldPredicate` — a `RowExpr` subject plus the
compared literal — as the one sealed spelling of the single-field-literal
equality; join the spellings that merge byte-neutrally; lower every
comparison through one shared builder; and fold the nineteen bounds
checks into one shared rule.**

The execution, per axis:

1. **Model — four spellings join, two stay put with their reasons
   recorded.** `FieldPredicate` (`subject : RowExpr`, `equals : String`,
   with `ofField` for the `Nat`-indexed producers) lives beside
   `RowExpr` in the view model. `RowGuard` was already exactly this
   shape and is replaced outright — `RowStage.removeIf` now holds an
   `Option FieldPredicate`, and the anonymous-constructor spelling
   `some ⟨.trim (.field i), ""⟩` is untouched by construction.
   `RowClassSelect` stores `predicate : FieldPredicate` in place of its
   `field`/`equals` pair; `Update.regionRemoveIf` takes the predicate in
   place of its positional `field`/`equals` args (so
   `regionRemoveIfTargets` now carries the whole predicate, literal
   included); `RegionFilter.arms` becomes
   `List (String × FieldPredicate)`. The two non-joiners:
   `RowReflect`'s `checkedIf` literal stays inside `RowReflectTarget`
   because the literal *is* the target discriminant — the value/checked
   distinction — and restructuring it would add representable states for
   zero deduplication; the anonymous `Option (Nat × String)`
   count/hidden/checked predicate keeps its pair spelling because it is
   the one pre-existing shared spelling, and renaming it would churn the
   mounted-split plumbing and the `select:…:{field}:{equals}` debug
   strings without removing any duplication. Both join at the builder
   instead.
2. **Backend — one shared comparison builder, scan loops excluded.**
   `fieldPredicateJs` emits
   `.binary .eq (rowExprJs subject) (.literal (.string equals))`;
   because `rowExprJs (.field i)` produces exactly the
   `item[field + 1]` subtree the seven sites hand-built — class
   selection, predicate removal, count scan, hidden/checked scan,
   filter arm, branch mount, branch update — and the printer is a pure
   function of the AST, the printed output is unchanged by
   construction. The reflect and row-guard sites, which already lowered
   their subjects through `rowExprJs` and hand-appended only the
   equality, route through the same builder. The surrounding scan loops
   are shared by nothing: the per-feature ident prefixes
   (`count_scan_*`, `hidden_row_*`, `kept_*`, `row_guard`) are golden
   contracts the artifacts assert verbatim.
3. **Validator — one bounds rule for nineteen blocks.** Every
   out-of-bounds message was already the same sentence behind a varying
   subject phrase — `"… field {i} outside region {name}'s {n}
   field(s)"` — so `checkFieldBound` takes the code, the subject
   phrase, the field, the region, and the site's exact path and spans,
   and each of the nineteen sites keeps its error code and message
   string byte-for-byte (the five row-template/aggregate codes
   LRX-VIEW-026/031/038/040/042 and the region-table codes
   LRX-TYPE-111/112/113/116 alike).
4. **The representability trade is named, not hidden.** Storing a
   `RowExpr` subject where a `Nat` sat makes non-field subjects
   representable in the merged spellings at the model level — the same
   level of representability the ADR-0049 reflect subject has always
   had. The seal is where it has always been: the surface elaborator
   only produces `.field` (or the guard's `.trim (.field i)`) there,
   the validator bounds-checks every projected field reference, and the
   guard-subject rule (`LRX-VIEW-040`) still rejects every non-subject
   guard shape.

## Open questions

1. **The six longhand `fields.idxOf?` elaborator sequences stay.** They
   are surface-resolution sites, each owning a distinct error message
   and repair hint; folding them would trade named, greppable error
   text for a parameterized helper with no output change to protect the
   trade. Left for a future round if their count grows.
2. **The carried rejections stand.** Affordance-contract checking
   (ADR-0059), the component payload single-position rule (ADR-0061),
   attribute-position count labels and the two-threshold grammar
   (ADR-0062), and negated or composed predicate subjects remain
   rejected or untouched.

## Consequences and limitations

- Every lab, example, and the benchmark bundle emit byte-identical
  JavaScript — the artifacts gates and the size gate are the evidence —
  and no manifest changes: no feature stamp moved and the runtime ABI
  stays 17. The freeze holds with nothing re-run; regression watch
  only.
- The dispatcher, `reconcile6`, the row vocabulary, and the host ABI
  are untouched; the key set stays sealed at Enter/Escape; the guard
  literal stays `""`; the count-label literal stays one; row guards
  stay single-field remove-or-commit; row scope still has no `s!`;
  branch cells stay single-level two-branch with exact click/dblclick
  agreement; and the parent-disposer instrumentation gap is unchanged.
- `RowGuard` no longer exists as a name; ADR-0053's
  `RowGuard.mk field literal` spelling reads as
  `FieldPredicate.mk subject literal` today. The audit manifest entry
  moved with it (`FieldPredicate.mk.injEq`).
- Lean-side test assertions that spelled the old shapes (class-selection
  tuples, removal targets, filter-arm triples) now spell the predicate;
  the removal-target assertions got strictly stronger, since the
  predicate carries the literal the old `(String × Nat)` pair dropped.

## Confirmation

The full gate suite is green (`check.sh`: build, native tests, graph
properties, differential, component codegen, region/effect runtime,
CLI, browser, benchmark size gates, bench, examples, compile-fail,
placeholders, axioms, semantic safety), with every generated artifact
byte-identical — `git status` shows no generated `.mjs` or manifest
change, and the js-framework-benchmark size gate passed against the
checked-in byte-identity baseline. After the refactor, no
`.binary .eq` over a hand-built `(uint (field + 1))` projection remains
in the component backend (the surviving `field + 1` sites are the
`rowExprJs` definition itself, the persistence serializer, the
`fieldText` projection, and assignment writes — projections, not
comparisons), and the nineteen `outside region` bounds messages are
produced by exactly one helper.
