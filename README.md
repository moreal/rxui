# LeanRx

LeanRx is a Lean 4-hosted frontend language and compiler experiment. It is being
implemented milestone by milestone against [ARCHITECTURE.md](ARCHITECTURE.md)
and [PLAN.md](PLAN.md). The repository is not yet a released framework.

## Prerequisites

- Elan with the toolchain named in `lean-toolchain` (Lean 4.33.0)
- Git
- Node.js is introduced when the JavaScript backend reaches M3
- pnpm is introduced when browser tooling first requires it

## Reproducible commands

```sh
lake build
lake exe leanrx_test
./scripts/check_placeholders.sh
./scripts/test_placeholder_scanner.sh
```

The same commands run in CI. See [STATUS.md](STATUS.md) for the current
milestone, exact baseline, and the latest green commit.

## Project boundaries

LeanRx compiles a restricted staged language; it does not transpile arbitrary
Lean. Unsupported browser constructs will be build errors. The intended backend
is a project-owned Reactive IR and typed JavaScript AST, with a small direct-DOM
host. Formal claims are limited to the pure Lean semantics and explicitly proved
theorems; generated JavaScript and browser behavior remain in the documented
trusted computing base.

No project license has been selected. `NOTICE.md` records prior-art provenance;
it does not grant a license to this repository.
