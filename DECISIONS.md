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

The governing decision process is described in `ARCHITECTURE.md` and `PLAN.md`.
New accepted ADRs may refine those documents only when the rationale, migration
impact, contract updates, and tests are committed together.
