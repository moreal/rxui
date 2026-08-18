# Status

## Current milestone

M0 — Repository bootstrap and guardrails

## Last green commit

`14d44a6 chore(repo): initialize LeanRx Lake package`

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

## In progress

- M0 policy checks, ADRs, prior-art notes, and CI.

## Next

- Close M0 with all documented gates green and independent review notes.
- Begin M1 with typed schemas and fields.

## Known blockers

- None.

## Commands

- `lake build`
- `lake exe leanrx_test`
- `./scripts/check_placeholders.sh`
- `./scripts/test_placeholder_scanner.sh`
