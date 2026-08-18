# Qed prior-art review

Reviewed on 2026-08-19 from the upstream repository:
<https://github.com/JacobAsmuth/qed>.

Qed is an MIT-licensed Lean 4 frontend framework. Its public repository describes
a typed Virtual DOM, Elm-style application/update model, direct value patches for
known bindings, routing, schemas, effects, SSR/hydration, browser examples, and a
Lean compiler-IR to JavaScript backend. The backend documents a bounded but
release-sensitive `Lean.IR` surface, a JavaScript runtime ABI, and fail-loud
handling for constructs it cannot lower.

## Relevant lessons

- Keep the handwritten DOM/driver boundary small and explicit.
- Treat examples and browser tests as a guided regression suite.
- Differentially test JavaScript output against native Lean behavior.
- Scan for proof placeholders and maintain an axiom policy.
- Document every Lean-version-dependent backend API.
- Preserve license and source provenance for any future adaptation.

## Deliberate differences

LeanRx centers dependency-indexed expressions, a statically known fine-grained
graph, actual-change propagation, and direct DOM sinks. It owns a restricted
Reactive IR instead of initially translating broad Lean compiler IR. Its central
proof compares optimized static-DAG propagation with full recomputation; it does
not reuse Qed's VDOM diff proof as a substitute.

## Reuse policy

Concepts and public architectural observations may inform LeanRx. No Qed source is
currently copied or adapted. Any future code reuse must first record the exact
upstream revision, MIT license notice, affected files, and modifications in
`NOTICE.md` and source comments.
