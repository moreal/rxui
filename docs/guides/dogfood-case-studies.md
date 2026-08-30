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
spans, toggle payload drift, and source-write undercounting. This app predates
the component-command surface: its dynamic-region event wiring is a
handwritten-backend-era case, not the sealed vocabulary below.

## Toggle Lab — component-command TodoMVC parity

Toggle Lab (after the Nest, Filter, and Branch labs before it) rebuilt TodoMVC's
interactions on the sealed component-command surface, one contract per round:
keyed regions and immutable props, typed row events, branch cells, row focus,
delegated dblclick/checked toggles, counts/broadcasts/removeIf, filter views,
row and component key branching, remove-if/skip-if guards, expression trim,
hidden/checked/disabled attribute selections, the count label, and finally hash
routing and storage persistence. Twenty-two ADRs (0043–0064) and two runtime ABI
bumps (16 focus, 17 route/persist) closed interaction parity, each surface
pinned by compile-fail fixtures, browser gates, and byte-level artifact checks.

The arc's cross-cutting lesson is a sealed-surface extension convention: each
round adopts exactly the one contract its parity gap demands and rejects
speculative vocabulary on the record (negated/composed subjects, two-threshold
grammars, and positional count labels all carry recorded rejections). Under the
byte-identical performance freeze, host extension is governed by reachability —
the compactor prunes exports the benchmark never names, so ABI 16 and 17 both
shipped with the benchmark bundle byte-identical (ADR-0048/0063 precedent).
Round-by-round records live in `DOGFOOD.md`.

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

The seven-page site is one public component built on reusable `LeanRx.Docs` and
`LeanRx.UI` source modules. State-driven native navigation owns six derived page
values, six text sinks, fourteen active-navigation attribute selections,
deterministic graph artifacts, editor declarations, a source-preserving Markdown
guide tree, a Tailwind v4 stylesheet, and one atomic production bundle. Browser gates cover
keyboard selection, `aria-pressed`, desktop and 375px layouts, 44px targets,
axe, isolation, disposal, and an exact eight-transition work snapshot.

The Tailwind integration is real source detection over `.lean` files and a CLI
compile in the atomic staging directory, not a CDN demo. The small UI kit adopts
shadcn's source-ownership idea but does not claim direct compatibility: shadcn's
React components cannot run in LeanRx's controlled direct-DOM component model.

Self-hosting still exposes product gaps. ADR-0063's sealed hash route table is
not a general docs router; Markdown is exported but not ingested; there is no
link/URL attribute, clipboard, search, SSR, hydration, interactive graph
explorer, accessible overlay primitive set, or installable Lean component
registry. The build records those boundaries instead of hiding them. Full
details and exact instrumentation live in `DOGFOOD.md`.

## Cross-cutting lesson

The recurring defects were not “Lean cannot express this.” They were contract
drift across pure model, checked metadata, generated code, host behavior, tests,
and prose. LeanRx's most useful discipline is keeping those boundaries explicit:
one typed source where feasible, sealed checked artifacts, deterministic output,
adversarial native/browser evidence, exact proof footprints, and documentation
that distinguishes theorem from test and observation.
