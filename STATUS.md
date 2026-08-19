# Status

## Current milestone

M2 — Graph model, scheduling, and semantics

## Last green commit

`3491e8a fix(core): enforce staged type contracts`

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
- Completed M1 typed schemas/fields, canonical dependency sets, heterogeneous
  stores, sealed scalar runtime/equality plans, dependency-indexed expressions,
  native evaluation, and the structural `eval_congr_on_deps` proof.
- Added the public Expression Playground and deterministic example-output gate.
- Compile-fail contracts reject raw dependency construction, unsupported staged
  reads, and primitive ABI remapping.
- Verified `3491e8a` from a fresh clone with `./scripts/check.sh`; 178 public
  theorems, 49 exact reviewed axiom uses, and 13 exact generated unsafe helpers
  passed, and the checkout remained clean.

## In progress

- Static source/derived/sink graph representation and deterministic validation.

## Next

- Define stable graph node IDs/kinds and direct-dependency specifications.
- Add source-linked validation, cycle paths, and deterministic topological ranks.
- Implement reference then optimized abstract graph semantics before browser code.

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

## M1 independent review notes

- Lean/toolchain: PASS at `3491e8a`; private dependency construction, universe
  coverage, indexed ABI, evidence-carrying reads, and full local gate verified.
- Type theory/proof: PASS; `eval_congr_on_deps` is structurally complete. Its
  exact `[propext, Quot.sound]` footprint is disclosed and locked by the audit.
- Compiler/backend: PASS; runtime types seal primitive ABI mappings, equality
  lowering derives from representation, and native modulo/Nat edge semantics are
  pinned for M3.
- Frontend/runtime: PASS; public staged reads reject unsupported runtime types,
  debug output is quoted, and no DOM/runtime implementation was introduced early.
- Test/quality: PASS after workspace and fresh-clone runs; distinct conditional
  branches, Type-1 store retrieval, hostile debug strings, compile-fail contracts,
  all primitives, Unicode, and unbounded Int behavior are covered.

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
