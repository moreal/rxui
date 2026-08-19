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

The governing decision process is described in `ARCHITECTURE.md` and `PLAN.md`.
New accepted ADRs may refine those documents only when the rationale, migration
impact, contract updates, and tests are committed together.
