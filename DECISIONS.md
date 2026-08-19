# Architecture decisions

| ADR | Status | Decision | Date |
|---|---|---|---|
| [0001](docs/adr/0001-lean-host-language.md) | Accepted | Lean 4 is the host language | 2026-08-19 |
| [0002](docs/adr/0002-staged-reactive-core.md) | Accepted | A typed staged DSL is the semantic boundary | 2026-08-19 |
| [0003](docs/adr/0003-custom-reactive-ir-js-backend.md) | Accepted | Use a custom Reactive IR to JavaScript backend | 2026-08-19 |
| [0004](docs/adr/0004-direct-dom-static-shape.md) | Accepted | Use direct DOM updates for static shape | 2026-08-19 |
| [0005](docs/adr/0005-trust-boundary.md) | Accepted | Limit proof claims and document the remaining TCB | 2026-08-19 |
| [0006](docs/adr/0006-scoped-component-jsx-syntax.md) | Accepted | Use scoped balanced component and JSX syntax | 2026-08-19 |

The governing decision process is described in `ARCHITECTURE.md` and `PLAN.md`.
New accepted ADRs may refine those documents only when the rationale, migration
impact, contract updates, and tests are committed together.
