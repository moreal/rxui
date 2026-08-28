# ADR-0074: Children on spec-less capitalized heads are rejected, in both views

- Status: Accepted
- Date: 2026-08-28
- Closes: ADR-0073 OQ1 (spec-less silent child drop), ADR-0073 OQ2
  (logical fallback asymmetry)

## Context

ADR-0073 guarded the typed view's `componentCall` fallback for heads
that *do* resolve to a checked spec (LRX-ELAB-132), and left two open
questions. OQ1: a *spec-less* capitalized head with non-empty children
silently drops them — `componentCall` receives attributes only, so the
children never reach the application. OQ2: the logical reference
view's `logicalElement` fallback calls `componentCall` unguarded, so
it shares the drop, and a spec'd head there dies with the raw
unknown-identifier error the typed view just fixed.

This round reproduced both on a `Test/Elab/ViewSurface.lean`-derived
copy. Typed: `<Metric value={metricValue}> ["extra"]` (where `Metric`
is the live ADR-0039 template function) compiled without any
diagnostic, `spec.check` and `Backend.Component.emit` succeeded, and
the printed module contained no `"extra"` — the child vanished with no
error and no render. Logical: `<LogicalMetric label="m"> ["extra"]`
produced `element "main" [] [element "p" … [text "m"]]` — same silent
drop. And a spec'd `<Chip tag="x"/>` under a `Region.LogicalNode`
expected type still reported the bare ``Unknown identifier `Chip``,
reconfirming OQ2's misleading death.

Is rejecting the children-bearing spec-less head a violation of the
sealed ADR-0039 contract ("a head without a checked spec keeps its
ordinary typed-application meaning")? No: the ordinary meaning is the
application of the head to its rewritten *attributes*. JSX children
were never part of that application — no program can observe them, so
no working surface can depend on writing them. Rejecting the shape
turns dead syntax into a diagnostic; the sealed surface — spec-less
heads with attributes and *no* children — elaborates byte-identically
through the guard's fall-through.

## Decision

**Reject non-empty children on a spec-less capitalized head with
`LRX-ELAB-133`, and route the logical fallback through the same
guard.** `leanrx_jsx_component_fallback%` gains a `childCount` numeral
(chosen at macro time, where the shape is visible, like the reason
string):

- head resolves to `{name}_spec` → `LRX-ELAB-132` with the macro-chosen
  reason (unchanged, ADR-0073);
- otherwise, `childCount != 0` → `LRX-ELAB-133`: the head "is an
  ordinary application (ADR-0039) and consumes no children — its
  content is the application's own result, so the children here would
  be dropped";
- otherwise → `Term.elabTerm` of the identical application term
  (ADR-0039 untouched).

`logicalElement` now emits the same wrapper for capitalized heads
instead of the bare `componentCall`, with its own reason for the
spec'd arm: "checked components nest in the typed component view only
— the logical reference view lowers ordinary applications". The
logical lowering had no live capitalized-head users (the survey found
none outside compile-fail fixtures), so no passing surface moves.

Witnesses, all registered in `scripts/check_compile_fail.sh`:

- `Test/fixtures/compile-fail/TemplateCallWithChildren.lean` — typed
  view, spec-less `Metric` head with `["extra"]` → LRX-ELAB-133;
- `Test/fixtures/compile-fail/ChildRefInLogicalView.lean` — logical
  view, checked `Chip` reference → LRX-ELAB-132 (was raw
  unknown-identifier);
- `Test/fixtures/compile-fail/TemplateChildrenInLogicalView.lean` —
  logical view, spec-less head with children → LRX-ELAB-133.

The surviving pass-throughs are pinned by passing tests:
`<Metric value={metricValue}/>` in `Test/Elab/ViewSurface.lean`
(typed, pre-existing) and a new `logicalDashboard` in the same file —
`<LogicalMetric label="m"/>` under `Region.LogicalNode`, compared
against the hand-written node — the first live logical-view
application surface.

The change is elaborator-only and error-path-only: no generated
module, manifest, or host byte moves.

## Consequences

- The misuse map for capitalized heads is closed in both views:
  LRX-ELAB-112 (spec'd, right shape, wrong prop names/order),
  LRX-ELAB-130 (forwarding into a spec-less head), LRX-ELAB-131 (any
  head in a sealed row template), LRX-ELAB-132 (spec'd head, shape
  outside the child-reference contract — now also any spec'd head in
  the logical view), LRX-ELAB-133 (spec-less head, non-empty
  children — nothing consumes them).
- No silent-drop path remains: every capitalized-head shape either
  renders, elaborates as an ordinary application, or names its
  contract.
- OQ1: the guard reads the child *count* only. If a future round wants
  spec-less heads to consume children (template functions taking a
  `View` list), the numeral is already at the fallback and the arm is
  the natural place to build the argument instead of throwing.
