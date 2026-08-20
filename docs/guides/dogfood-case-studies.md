# Dogfood case studies

LeanRx's applications are architecture probes, not showcase wrappers. Every app
imports public APIs, compiles in CI, exercises a native/browser scenario, records
friction in `DOGFOOD.md`, and turns discovered defects into regressions.

## Expression Playground — typed staged values

The first public app established schema fields, dependency-indexed expressions,
native stores, stable debug output, Bool/String/Int/Nat primitives, and JS BigInt
semantics. It exposed universe-generalization, canonical dependency-set, runtime
representation/equality, and string-escaping issues before components existed.

## Graph Lab and Diamond — schedules and transactions

Graph Lab forced deterministic graph construction, source-linked cycle errors,
topological schedules, reference/affected execution, property tests, and the
single-declaration all-Int proof bridge. Diamond later exercised a real fan-in
transaction: two branches update, the fan-in observes only the final pair, and
the browser never exposes an intermediate value.

## Counter — direct DOM and safe static views

Counter introduced the checked component surface, typed JavaScript AST, direct
text sinks, native buttons, per-mount state, equality stops, sink caches, disposal,
hostile text, manifests, atomic output, and Chromium/axe gates. It found role/name
surface drift, generic cycle diagnostics, mutable instrumentation, and incomplete
same-value coverage.

## Dependent Tabs — proof erasure

Tabs carries equal nonempty vectors and `Fin` selection/event payloads from Lean
to one checked array access. It made erased proof dependence observable and led
to a structural no-inspection theorem plus ABI metadata. Runtime review caught
same-selection work, equal-output sink writes, missing selected-state semantics,
and hostile strings in the specialized backend path.

## Temperature Converter and Validated Form — controlled input/refinement

Temperature preserves invalid raw input/cursor and converts only a closed ASCII
integer grammar. Its complete checked state includes active scale so presentation
is not event-history dependent. Validated Form seals nonempty/bounded/accepted
refinements and a fake command capability. Adversarial review found native/JS
underscore grammar drift, stale submit before blur, incomplete effective writes,
ARIA error gaps, and unredacted key traces.

## TodoMVC — dynamic local regions

TodoMVC adds conditional edit/view branches, positional filter controls, and keyed
rows without a root VDOM. It validates unique/fresh reachable region state,
preserves keyed/focus identity, disposes nested branches, and differentially
compares the complete native logical projection. Bugs included native/generated
draft drift, unscoped delegated Enter, inaccessible row checkboxes, click-only
spans, toggle payload drift, and source-write undercounting.

## Notes and Issue Browser — owned effects

Notes owns restore, replaceable debounce, save, visible storage failures, and
disposal cancellation. Issue Browser adds HTTP, typed exact decoding, pagination,
retry, stale suppression, and duplicate-key rejection. Review hardened effect
generation matching, remove-before-cancel, throwing/reentrant cleanup, blocked
storage getters, delivery failures, safe integer/JSON lexeme agreement, and
large-exponent totality.

## Data Grid — structural delta decision

The fixed 10,000-row trace compares full keyed recomputation, checked `ListDelta`,
and a hybrid cost model. Full logical oracles and exact copied work counters caught
reverse-as-sort, unlowered accepted cost parameters, same-key swap corruption,
invalid action crashes, false initial state, ABI metric misuse, retained listener
closures, and endpoint-only comparison. Measurements show workload-specific
retained-work wins but identical emitted DOM-write totals, so ADR-0017 keeps delta
opt-in. See the [performance report](../performance/m10-data-grid.md).

## LeanRx documentation site — self-hosting

The seven-page site is itself one public component with state-driven native
navigation, three derived page values, direct text sinks, deterministic graph
artifacts, editor declarations, an atomic production bundle, hostile-text checks,
keyboard/axe coverage, isolation, disposal, and an exact work snapshot. It uses
LeanRx for the application rather than another framework.

Self-hosting exposed current learnability/product gaps: there is no URL router,
semantic navigation/link/code/list vocabulary, typed CSS, SSR, hydration, or
interactive graph explorer. The build keeps a small handwritten HTML/CSS boot
shell and records that boundary instead of hiding it. Full details and exact
instrumentation live in `DOGFOOD.md`.

## Cross-cutting lesson

The recurring defects were not “Lean cannot express this.” They were contract
drift across pure model, checked metadata, generated code, host behavior, tests,
and prose. LeanRx's most useful discipline is keeping those boundaries explicit:
one typed source where feasible, sealed checked artifacts, deterministic output,
adversarial native/browser evidence, exact proof footprints, and documentation
that distinguishes theorem from test and observation.
