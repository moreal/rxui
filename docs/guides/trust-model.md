# LeanRx trust model

LeanRx separates kernel-checked statements from compiler/runtime/browser evidence.
No claim on this page extends beyond the theorem statements and exact audits in
the repository.

## What Lean proves

The project has named kernel-checked results for selected pure layers, including:

- staged expression evaluation depends only on its typed dependency set;
- the finite all-Int abstract optimized step agrees with full recomputation under
  the stated well-formedness, cache-validity, and transaction hypotheses;
- nested source writes flatten with preserved order, changed-ID tracking, and the
  documented flattened-write specialization of optimized/reference agreement;
- proof erasure inspection reports no proof-dependent runtime inspection for the
  closed Reactive IR;
- conditional, positional, and keyed pure region planners preserve their logical
  target projections;
- accepted structural delta plans apply to their independently supplied target;
- selected reset/planner laws and typed vector/dependency lemmas.

Read the theorem types in `LeanRx/Proofs`, `LeanRx/IR/Erasure.lean`,
`LeanRx/Region`, and `LeanRx/Collection/Delta.lean`. Names such as “optimized” or
“correct” do not prove performance, JavaScript extraction, DOM identity, or host
cleanup unless those properties appear in the type.

## Exact axiom and unsafe policy

All Lean sources compile with `hasSorry` promoted to an error. Repository gates:

- reject placeholders, `native_decide`, and unreviewed axiom/constant syntax;
- enumerate every public `LeanRx.*` theorem and compare its exact axiom footprint;
- enumerate exact generated unsafe helpers and public unsafe declarations;
- reject written `unsafe`/`partial` declarations in verified semantic paths;
- protect private proof/validation-bearing constructors with compile-fail tests.

Reviewed footprints use only the explicitly recorded Lean kernel/library axioms
such as `propext` and generated `Quot.sound` equation dependencies where named in
[ADR-0005](../adr/0005-trust-boundary.md). Many theorems are axiom-free. The audit
is exhaustive for imported public LeanRx theorems; it is not a claim that Lean's
kernel or toolchain implementation is infallible.

## Remaining trusted computing base

The following are not formally verified by LeanRx:

- Lean's kernel, compiler, elaborator, standard library, Lake, and exact toolchain;
- MD4Lean's Lean/FFI wrapper and its vendored MD4C parser for documentation builds;
- the component extraction and specialized application backends;
- proof erasure implementation beyond the closed structural analyzer theorem;
- JavaScript AST validation/printer implementation and the JS engine;
- browser DOM, events, focus, accessibility tree, timers, promises, storage,
  networking, `AbortController`, URL encoding, and garbage collection;
- the tiny JavaScript hosts and foreign cancellation/port callbacks;
- POSIX link/rename/locking behavior and hostile concurrent filesystem races;
- native/JavaScript decoder duplication and application-specific generated state
  machines except where pure theorems explicitly connect their inputs/outputs;
- browser instrumentation, latency, allocation, memory, and accessibility tools.

These boundaries receive native, differential, deterministic, fake-host,
adversarial, and real Chromium tests. Tests are evidence, not proofs.

## Checked boundaries that reduce the TCB surface

- `Field`, `RxExpr`, `RuntimeType`, and private constructors make invalid typed
  states hard or impossible to express through public APIs.
- `ComponentSpec.check` and specialized checkers validate roles, graph shape,
  source spans, event targets, representations, and accessibility guardrails.
- private `PlannedGraph`, checked component, region result, refinement, command,
  and structural plan constructors prevent caller-forged certificates.
- `Js.Module.validate` checks binding identifiers, lexical collisions, safe
  globals, references, exports, and dynamic-code exclusions before printing.
- manifests disclose the exact ABI/features/ports consumed by the browser.
- whole-batch region/decoder validation occurs before DOM or state mutation.
- owned effect completion is tied to an exact entry, preventing stale numeric
  handle reuse from completing a replacement.

## Formal-claim reading guide

When evaluating a statement, ask:

1. Is it a theorem, a pure checker result, a native test, a differential test, a
   fake-host test, a Chromium test, or a measurement?
2. What hypotheses and value subset does its type cover?
3. Does it mention JavaScript/DOM behavior, or is that an inference across the TCB?
4. Does an ADR record its axiom footprint and remaining assumptions?
5. Can the exact command be reproduced from `README.md` or the relevant report?

The repository intentionally phrases browser results as “tested,” “observed,” or
“demonstrated,” not “proved.” Report any prose that crosses that boundary.

## Reproduce the trust gates

```sh
lake build
lake exe leanrx_test
./scripts/check_compile_fail.sh
./scripts/check_placeholders.sh
./scripts/test_placeholder_scanner.sh
./scripts/check_axioms.sh
./scripts/check_semantic_safety.sh
```

The complete native/differential/browser suite is `./scripts/check.sh`.
