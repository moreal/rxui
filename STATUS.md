# Status

## Current milestone

M1 — Typed staged expression core

## Last green commit

`f6dd63b fix(policy): audit imported Lean declarations`

## Baseline (2026-08-19, Asia/Seoul)

- Initial workspace contained only `ARCHITECTURE.md` and `PLAN.md`.
- No Git metadata, Rust source, `.rxui` source, Lean source, or package manifest existed.
- `git branch --show-current` failed with “not a git repository”.
- Lean: `4.33.0` (`d8b18978322de05a8f3dba51ef03cf5461676c17`).
- Lake: `5.0.0-src+d8b1897`.
- Node: `v22.23.2`.
- pnpm: unavailable and intentionally not installed before JavaScript tests exist.
- First `lake build` exposed a root module doc-comment parse error; after correction,
  `lake build` and `lake exe leanrx_test` passed.

## Completed

- Read the architecture and implementation contracts in full.
- Confirmed that there is no prior Rust or `.rxui` implementation to migrate.
- Initialized Git on `main` without altering the two supplied contract documents.
- Pinned Lean 4.33.0 and added a minimal Lake library and native smoke executable.
- Completed M0 ADRs, prior-art/provenance review, status/dogfood/upgrade docs,
  formatting and shell lint, proof-placeholder regressions, environment axiom and
  safety audits, and SHA-pinned CI.
- Added deterministic source-span types as the first nonempty Core layer anchor.
- Verified `f6dd63b` from a fresh local clone with `./scripts/check.sh`; all gates
  passed and the clone remained clean.
- Audited 14 public LeanRx theorems. The only axiom uses are the two exact,
  documented, Lean-generated `SourcePos.mk.injEq`/`SourceSpan.mk.injEq → propext`
  pairs.

## In progress

- Typed schema, field, dependency-set, and heterogeneous-store design for M1.

## Next

- Implement typed schemas and fields in a small buildable commit.
- Add canonical dependency sets, the logical store, and their laws/tests.
- Implement dependency-indexed scalar expressions and native evaluation.

## Known blockers

- None.

## M0 independent review notes

- Lean/toolchain: PASS at `f6dd63b`; exact fixed toolchain, import sentinels,
  internal test API inventory, and full local gate verified.
- Type theory/proof: PASS; `hasSorry`, public axiom/theorem dependency,
  `native_decide`, and unsafe/partial policies fail closed for the current scope.
- Compiler/backend: PASS; minimum Core layering exists and the staged-core,
  custom Reactive IR, deterministic JS AST, CLI, and host boundaries remain intact.
- Frontend/runtime: PASS; no premature runtime exists, and future DOM/security/
  accessibility gates are captured in the contracts and CI-ready policy.
- Test/quality: PASS after a fresh-clone run; all 13 implementation commits have
  conventional subjects and exactly one required assistance trailer.
- History note: `29e61b0` documented two policy commands one commit before they
  landed in `a0dba53`. Its build and native test remained green. Review recommended
  preserving history rather than rewriting descendants; future documentation and
  its referenced scripts must land together.

## Commands

- `./scripts/check.sh`
- `./scripts/check_format.sh`
- `lake build`
- `lake exe leanrx_test`
- `./scripts/check_examples.sh`
- `./scripts/check_compile_fail.sh`
- `./scripts/check_placeholders.sh`
- `./scripts/test_placeholder_scanner.sh`
- `./scripts/check_axioms.sh`
- `./scripts/check_semantic_safety.sh`
