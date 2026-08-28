# Architecture decisions

| ADR | Status | Decision | Date |
|---|---|---|---|
| [0001](docs/adr/0001-lean-host-language.md) | Accepted | Lean 4 is the host language | 2026-08-19 |
| [0002](docs/adr/0002-staged-reactive-core.md) | Accepted | A typed staged DSL is the semantic boundary | 2026-08-19 |
| [0003](docs/adr/0003-custom-reactive-ir-js-backend.md) | Accepted | Use a custom Reactive IR to JavaScript backend | 2026-08-19 |
| [0004](docs/adr/0004-direct-dom-static-shape.md) | Accepted | Use direct DOM updates for static shape | 2026-08-19 |
| [0005](docs/adr/0005-trust-boundary.md) | Accepted | Limit proof claims and document the remaining TCB | 2026-08-19 |
| [0006](docs/adr/0006-scoped-component-jsx-syntax.md) | Accepted | Use scoped balanced component and JSX syntax | 2026-08-19 |
| [0007](docs/adr/0007-atomic-versioned-output.md) | Accepted | Publish versioned bundles through an atomic pointer | 2026-08-19 |
| [0008](docs/adr/0008-runtime-abi-v2.md) | Accepted | Bump the internal runtime ABI for M5 transactions | 2026-08-19 |
| [0009](docs/adr/0009-m5-benchmark-smoke-scope.md) | Accepted | Treat the M5 graph runner as a pre-benchmark smoke harness | 2026-08-19 |
| [0010](docs/adr/0010-runtime-abi-v3-dependent-values.md) | Accepted | Bump the internal runtime ABI for dependent values and typed event payloads | 2026-08-19 |
| [0011](docs/adr/0011-fin-literal-normalization.md) | Accepted | Exclude modulo-normalized `Fin` literals from public selection construction | 2026-08-19 |
| [0012](docs/adr/0012-poc-dogfood-set.md) | Accepted | Align the PoC dogfood set with M0–M6 and defer Temperature Converter to M7 | 2026-08-19 |
| [0013](docs/adr/0013-runtime-abi-v4-form-events.md) | Accepted | Bump the internal runtime ABI for typed form properties and payload events | 2026-08-19 |
| [0014](docs/adr/0014-runtime-abi-v5-dynamic-regions.md) | Accepted | Bump the internal runtime ABI for local dynamic regions and delegated row events | 2026-08-19 |
| [0015](docs/adr/0015-runtime-abi-v6-owned-effects.md) | Accepted | Bump the internal runtime ABI for owned commands and explicit foreign ports | 2026-08-20 |
| [0016](docs/adr/0016-runtime-abi-v7-structural-deltas.md) | Accepted | Bump the internal runtime ABI for checked structural keyed deltas | 2026-08-21 |
| [0017](docs/adr/0017-structural-delta-remains-opt-in.md) | Accepted | Keep structural delta an opt-in experimental library | 2026-08-21 |
| [0018](docs/adr/0018-runtime-abi-v8-template-clone.md) | Accepted | Bump the internal runtime ABI for template cloning and minimal keyed placement | 2026-08-22 |
| [0019](docs/adr/0019-runtime-abi-v9-owned-parent-rebuild.md) | Accepted | Bump the internal runtime ABI for owned-parent rebuilds, property keys, and a separate delta host | 2026-08-22 |
| [0020](docs/adr/0020-runtime-abi-v10-keyed-context-and-update-at.md) | Accepted | Bump the internal runtime ABI for keyed-region context forwarding and single-row updates | 2026-08-22 |
| [0021](docs/adr/0021-runtime-abi-v11-form-events-host.md) | Accepted | Bump the internal runtime ABI for a separate form-event host | 2026-08-23 |
| [0022](docs/adr/0022-runtime-abi-v12-disposer-in-dom-host.md) | Accepted | Bump the internal runtime ABI to ship the disposer in the DOM host | 2026-08-23 |
| [0023](docs/adr/0023-flattened-benchmark-module.md) | Accepted | Flatten the js-framework-benchmark application into one module at build time | 2026-08-23 |
| [0024](docs/adr/0024-compacted-benchmark-module.md) | Accepted | Compact the flattened js-framework-benchmark module with a Lean tokenizer | 2026-08-23 |
| [0025](docs/adr/0025-precedence-aware-javascript-printer.md) | Accepted | Print JavaScript expressions by operator precedence and drop effect-only returns | 2026-08-23 |
| [0026](docs/adr/0026-runtime-abi-v13-keyed-swap-and-remove.md) | Accepted | Bump the internal runtime ABI for keyed-region swap and single-row removal | 2026-08-23 |
| [0027](docs/adr/0027-monotone-keys-without-index.md) | Accepted | Validate monotone keys without an index in the keyed region | 2026-08-23 |
| [0028](docs/adr/0028-runtime-abi-v14-next-text.md) | Accepted | Bump the internal runtime ABI for text-slot traversal in the DOM host | 2026-08-23 |
| [0029](docs/adr/0029-safe-integer-benchmark-ids.md) | Accepted | Represent js-framework-benchmark row ids as safe integers | 2026-08-23 |
| [0030](docs/adr/0030-runtime-abi-v15-structural-delegation.md) | Accepted | Bump the internal runtime ABI for structural row-click delegation | 2026-08-23 |
| [0031](docs/adr/0031-pruned-benchmark-module.md) | Accepted | Drop unreachable host declarations from the flattened js-framework-benchmark module | 2026-08-23 |
| [0032](docs/adr/0032-structural-benchmark-buttons.md) | Accepted | Resolve the js-framework-benchmark buttons by structure | 2026-08-23 |
| [0033](docs/adr/0033-rx-expression-surface.md) | Accepted | Stage ordinary expression syntax with rx% | 2026-08-24 |
| [0034](docs/adr/0034-dual-target-jsx-surface.md) | Accepted | Lower one JSX surface into typed views and the logical region model | 2026-08-24 |
| [0035](docs/adr/0035-non-reserved-surface-keywords.md) | Accepted | Parse surface keywords as plain identifiers | 2026-08-24 |
| [0036](docs/adr/0036-component-item-sugar.md) | Accepted | Sugar component items and bind events by reference | 2026-08-24 |
| [0037](docs/adr/0037-typed-event-payloads-in-component-backend.md) | Accepted | Lower typed event payloads through the generic component backend | 2026-08-24 |
| [0038](docs/adr/0038-controlled-inputs-in-component-backend.md) | Accepted | Reflect controlled inputs through the generic component backend | 2026-08-25 |
| [0039](docs/adr/0039-static-child-component-composition.md) | Accepted | Compose stateful child components by static module import | 2026-08-25 |
| [0040](docs/adr/0040-app-ir-for-dynamic-region-events.md) | Accepted | Sketch an App IR to generalize Backend.Todo's event lowering | 2026-08-25 |
| [0041](docs/adr/0041-sealed-row-binders-for-keyed-regions.md) | Accepted | Bind keyed region rows through sealed row binders in the generic backend | 2026-08-25 |
| [0042](docs/adr/0042-immutable-props-across-the-mount-abi.md) | Accepted | Pass immutable child props as a positional mount ABI array | 2026-08-25 |
| [0043](docs/adr/0043-sealed-row-expressions-and-row-updates.md) | Accepted | Update keyed rows through sealed row expressions and updateAt | 2026-08-25 |
| [0044](docs/adr/0044-row-scoped-class-selection.md) | Accepted | Select row classes through a sealed row-scoped predicate | 2026-08-25 |
| [0045](docs/adr/0045-filter-region-as-static-view-selection.md) | Accepted | Express TodoMVC's filter row as static view with state-scoped selection | 2026-08-25 |
| [0046](docs/adr/0046-typed-row-event-payloads.md) | Accepted | Deliver typed row event payloads through structural delegation | 2026-08-25 |
| [0047](docs/adr/0047-sealed-row-branch-structure.md) | Accepted | Select conditional row structure through a sealed row branch cell | 2026-08-25 |
| [0048](docs/adr/0048-row-focus-vocabulary.md) | Accepted | Focus fresh row branch inputs through an explicit marker and host export | 2026-08-25 |
| [0049](docs/adr/0049-row-dblclick-and-checked-delegation.md) | Accepted | Extend the delegated row kinds with dblclick and checkbox toggles | 2026-08-26 |
| [0050](docs/adr/0050-row-aggregates-and-region-broadcasts.md) | Accepted | Count, broadcast into, and filter keyed rows through the region record | 2026-08-26 |
| [0051](docs/adr/0051-sealed-region-filter-views.md) | Accepted | Select keyed row visibility through a sealed filter table | 2026-08-27 |
| [0052](docs/adr/0052-sealed-row-key-branching.md) | Accepted | Branch keydown row events on sealed key literals | 2026-08-27 |
| [0053](docs/adr/0053-sealed-row-field-guards.md) | Accepted | Guard row stages on sealed field equality for remove-or-commit | 2026-08-27 |
| [0054](docs/adr/0054-sealed-row-expression-trim.md) | Accepted | Trim row expressions through one sealed unary for the commit contract | 2026-08-28 |
| [0055](docs/adr/0055-component-scope-add-path.md) | Accepted | Close the component-scope add path with the RxExpr trim and the sealed skip-if event guard | 2026-08-28 |
| [0056](docs/adr/0056-component-scope-key-branching.md) | Accepted | Close the Enter-to-add gap with the sealed key-branched component event | 2026-08-28 |
| [0057](docs/adr/0057-trimmed-attribute-selection.md) | Accepted | Extend the attribute-selection subject with the sealed trim unary for the Add affordance | 2026-08-28 |
| [0058](docs/adr/0058-empty-region-visibility.md) | Accepted | Close the hide-when-empty parity with the sealed region-subject hidden selection | 2026-08-28 |
| [0059](docs/adr/0059-predicate-count-visibility.md) | Accepted | Hide the clear-completed affordance through the sealed predicate-count hidden subject | 2026-08-28 |
| [0060](docs/adr/0060-region-checked-reflection.md) | Accepted | Reflect the sealed region-count boolean into the toggle-all checkbox's checked property | 2026-08-28 |
| [0061](docs/adr/0061-payload-broadcast.md) | Accepted | Flow the delegated checked payload into the region broadcast to close toggle-all | 2026-08-28 |
| [0062](docs/adr/0062-count-label-selection.md) | Accepted | Select between two static strings from a region count against the one literal — items-left singular/plural | 2026-08-28 |
| [0063](docs/adr/0063-freeze-boundary-routing-persistence.md) | Accepted | Take the parity axis: routing and persistence host exports as one ABI 17 round under the pruning-sealed freeze boundary; defer the field-predicate unification | 2026-08-28 |
| [0064](docs/adr/0064-field-predicate-unification.md) | Accepted | Unify the single-field-literal equality behind one sealed FieldPredicate, one shared comparison builder, and one bounds rule — byte-neutral under the freeze | 2026-08-28 |
| [0065](docs/adr/0065-affordance-contract-alignment.md) | Accepted | Reject the affordance-contract alignment check — affordance predicates are presentation policy and the dispatch layer stays the one contract | 2026-08-28 |
| [0066](docs/adr/0066-child-instrumentation-reachability.md) | Accepted | Reach child instrumentation through the parent disposer's `children` array — republish child mount returns in generated code; reject counter merging and host accessors | 2026-08-28 |
| [0067](docs/adr/0067-transitive-child-composition.md) | Accepted | Transitive child composition needs no new vocabulary — the ADR-0066 republication applies per level and `children[i].children[j]` is the composed surface, pinned by the two-level NestLab | 2026-08-28 |
| [0068](docs/adr/0068-parent-prop-forwarding.md) | Accepted | A child prop value may be exactly one declared immutable prop of the parent — `label={title}` lowers to a `ChildProp.forward` index and mounts as `props[i]`, still a mount-time constant; everything else stays rejected | 2026-08-28 |
| [0069](docs/adr/0069-transitive-prop-reforwarding.md) | Accepted | Transitive prop re-forwarding needs no new vocabulary — the forwarding rewrite never asks where the parent's value came from, so a chain is per-level ADR-0068 links, pinned by the three-level NestLab | 2026-08-28 |
| [0070](docs/adr/0070-fanout-prop-reforwarding.md) | Accepted | Fan-out prop re-forwarding needs no new vocabulary — the child table, aliased imports, and `children` republication all scale by declaration order, so two forwards of one received prop are independent ADR-0068 links, pinned by the `Chip` sibling leaf | 2026-08-28 |
| [0071](docs/adr/0071-repeated-child-composition.md) | Accepted | Repeated composition of the same child needs no new vocabulary — the table dedups by name (one aliased import) while every reference keeps its own `ChildProp` list and `child_off_{n}`, pinned by the second `Chip` instance mixing a forward with a literal | 2026-08-28 |
| [0072](docs/adr/0072-no-child-composition-in-region-rows.md) | Accepted | Sealed row templates do not compose child components — a capitalized head in a region row is a lifecycle-contract conflict, rejected at elaboration with the dedicated `LRX-ELAB-131` instead of the misleading tag-whitelist `LRX-VIEW-007` | 2026-08-28 |
| [0073](docs/adr/0073-misshapen-child-reference-diagnostic.md) | Accepted | A spec'd capitalized head whose shape leaves the child-reference contract is rejected at the typed-application fallback with `LRX-ELAB-132` — a term-elab guard where the spec is visible, replacing `Unknown identifier`; macro-time rejection is impossible without breaking the ADR-0039 spec-less application | 2026-08-28 |
| [0074](docs/adr/0074-spec-less-head-children-rejection.md) | Accepted | Non-empty children on a spec-less capitalized head are rejected with `LRX-ELAB-133` instead of vanishing silently — the ADR-0039 ordinary application consumes attributes only, so the children were dead syntax; the logical reference view routes through the same guard (spec'd head → `LRX-ELAB-132`, replacing the raw unknown-identifier), closing ADR-0073 OQ1/OQ2 | 2026-08-28 |
| [0075](docs/adr/0075-per-row-child-composition.md) | Accepted | Seal per-row child composition on the narrowest coherent surface — one self-closing child per row template, props as row-mount constants (literals or never-written row fields, `LRX-VIEW-045` otherwise), no static id in the child template (`LRX-ELAB-135`), mounted at its cell and disposed through the row dispose callback, republished on the live `children` inventory; everything else stays `LRX-ELAB-131`, closing ADR-0072 OQ1 with no host change | 2026-08-28 |
| [0076](docs/adr/0076-row-child-region-feature-coexistence.md) | Accepted | Row-child composition coexists with counts, filters, and persistence — the surveyed axes (slot arithmetic, hydration child context, filter row-root navigation, row-table-scoped subjects) are coherent, so the round gates the combination instead of sealing anything: Mix Lab puts all four features on one region and the artifact gate pins the widest 9-slot record layout and the `regions[0][8]` child context; no code change, ABI stays 17 | 2026-08-28 |
| [0077](docs/adr/0077-broadcast-and-shared-inventory-closure.md) | Accepted | Broadcasts retain row children and child-composing regions share one inventory — a broadcast retains every key so the reconcile never remounts a child, and the record construction hands every child-composing region the same `childInventory` identifier at its own `regionChildSlot`; Mix Lab gains a `markAllDone` broadcast and a bare `pins` region (the first two-region component), gates pin the two-record literal, both `indexOf` dispose splices, chronological cross-region interleaving, and splice isolation, plus a `RowChildBroadcastField` witness for the LRX-VIEW-045 broadcast-writer arm; no code change, ABI stays 17 | 2026-08-28 |
| [0078](docs/adr/0078-multi-region-feature-distribution.md) | Accepted | Region features distribute per region, and a component persists one key per region — the survey found per-region sweep identifiers, feature slots, count records, document-order attr labels, and cross-region chained events all coherent by construction, but `validatePersists` capped the whole component at one persist item while the backend was already index-generalized; the cap becomes one item per region with keys distinct across the component (both violations `LRX-TYPE-118`, the invariant is one writer per key), and Mix Lab's `pins` takes its own count, emptiness selection, persist key, and a chained `append pins … then remove crew …` event, with the artifact gate pinning crew's container and pins' inventory at the same slot number 7; ABI stays 17 | 2026-08-28 |
| [0079](docs/adr/0079-multi-filter-distribution.md) | Accepted | Filters distribute per region, including two driven by one state field — the survey found the scan identifiers, container slots (`5 + counts?2`), wake guards (`region_touched_{i} || changed[field]`), declaration-order sweep, and the region-keyed `validateFilters` all per-region by construction, with no scaffolding cap behind them, so the round gates the combination in a new Twin Lab (three filtered regions, twins over one field with inverted tables, a control on its own field, and a `stir` event mixing a region touch with a shared filter change) rather than in Mix Lab, whose evidence depends on `pins` staying unfiltered; `FilterRegionTwice` witnesses that two filters over one region stay `LRX-TYPE-113`; no code change, ABI stays 17 | 2026-08-28 |

The governing decision process is described in `ARCHITECTURE.md` and `PLAN.md`.
New accepted ADRs may refine those documents only when the rationale, migration
impact, contract updates, and tests are committed together.
