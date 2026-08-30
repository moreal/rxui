# LeanRx documentation

LeanRx is an unreleased Lean 4-hosted frontend compiler experiment. Start here:

## Choose a reading path

| Goal | Read in this order |
|---|---|
| Build and inspect the smallest component | [Getting started](guides/getting-started.md) → [Writing components](guides/components.md) → [Backend support](guides/backend-support.md) |
| Learn the complete authoring surface | [Writing components](guides/components.md) → [Language guide](guides/language.md) → the relevant internals page |
| Work on the compiler or runtime | [Architecture](guides/architecture.md) → [Trust model](guides/trust-model.md) → [Tooling](guides/tooling.md) → the relevant ADR |
| Evaluate project claims | [Philosophy](guides/philosophy.md) → [Trust model](guides/trust-model.md) → [Dogfood case studies](guides/dogfood-case-studies.md) |

The guides distinguish four kinds of capability: **supported** means the generic
checked backend owns it; **checked context** means it is available only through a
named dependent or feature-specific contract; **dogfood/experimental** means a
repository application exercises it without a general compatibility promise;
and **unsupported** means compilation must fail rather than silently escape to
JavaScript. The [backend support matrix](guides/backend-support.md) is the
authoritative quick reference for those labels.

## Guide index

1. [Getting started](guides/getting-started.md) — diagnose, scaffold, check, and build.
2. [Philosophy and operating model](guides/philosophy.md) — why the language is staged.
3. [Writing components](guides/components.md) — a complete component and authoring rules.
4. [Tailwind and UI integrations](guides/integrations.md) — tested support and honest limits.
5. [Language guide](guides/language.md) — the complete staged surface.
6. [Tooling guide](guides/tooling.md) — commands, artifacts, and verification gates.
7. [Backend support matrix](guides/backend-support.md) — what is actually lowerable today.
8. [Architecture guide](guides/architecture.md) — compiler layers, runtime, and artifacts.
9. [Trust model](guides/trust-model.md) — proved claims, exact audits, and remaining TCB.
10. [Accessibility guide](guides/accessibility.md) — encoded guarantees and manual review.
11. [Dogfood case studies](guides/dogfood-case-studies.md) — what each application found.

Reference material:

- [Transaction and instrumentation contract](internals/transactions.md)
- [Runtime representation](internals/runtime-representation.md)
- [Forms](internals/forms.md)
- [Dynamic regions](internals/dynamic-regions.md)
- [Effects and foreign ports](internals/effects.md)
- [M10 Data Grid performance report](performance/m10-data-grid.md)
- [js-framework-benchmark integration](performance/js-framework-benchmark.md)
- [Upgrading Lean](upgrading-lean.md)
- [Architecture decisions](adr/)

The normative product and delivery contracts remain
[`ARCHITECTURE.md`](../ARCHITECTURE.md) and [`PLAN.md`](../PLAN.md).
Repository evidence and the current green baseline are recorded in
[`STATUS.md`](../STATUS.md).

Documentation describes the current checkout, not a released version. When a
guide, generated artifact, and implementation disagree, treat the implementation
and the normative contracts as current, then report or correct the stale guide.
