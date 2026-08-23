# Status

## Current milestone

Complete — M0 through M11

## Last green commit

`d9c85ab test(docs): align final evidence claims`

## Baseline (2026-08-19, Asia/Seoul)

- Initial workspace contained only `ARCHITECTURE.md` and `PLAN.md`.
- No Git metadata, Rust source, `.rxui` source, Lean source, or package manifest existed.
- `git branch --show-current` failed with “not a git repository”.
- Lean: `4.33.0` (`d8b18978322de05a8f3dba51ef03cf5461676c17`).
- Lake: `5.0.0-src+d8b1897`.
- Node: `v22.23.2`.
- pnpm: unavailable at the initial baseline; M4 now pins Corepack pnpm 10.33.0.
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
- Completed M2 typed source/derived/sink graphs, validated stable IDs and direct
  dependency types, useful source-linked cycle paths, deterministic certified
  topological schedules/ranks, and pure JSON/DOT graph artifacts.
- Added full-recomputation and explicit changed-frontier abstract semantics with
  batched sources, pending/evaluated/changed traces, lawful equality stopping,
  sink suppression, and work instrumentation.
- Proved exact changed-frontier tracking, topological-prefix store equality,
  sink observation equality, reference cache initialization, and optimized
  next-state validity. Repeated optimized transactions require no reference-state
  oracle.
- Added the checked all-`Int` proof-subset bridge: graph metadata and abstract
  evaluators derive from the same dependency-indexed `RxExpr`; source/sink shapes,
  declaration-order restrictions, and private planned artifacts fail closed.
- Added replayable fixed-seed DAG properties, branch-complete graph diagnostics,
  graph serializer goldens, compile-fail planned-artifact construction, and the
  public Graph Lab with a measured parity stop (four reference evaluations versus
  one optimized evaluation).
- Verified `c1c071d` from a fresh local clone with `./scripts/check.sh`; 80 build
  jobs, 412 public theorems, 103 exact reviewed axiom uses, 22 exact generated
  unsafe recursion helpers, native/proof/property/example/negative/policy gates
  all passed, and the checkout remained clean.
- Completed M3's closed custom Reactive IR, validity-checked JavaScript AST,
  deterministic name allocator, readable/compact ESM printer, scalar runtime
  helpers, typed positional input ABI, and fail-closed backend diagnostics.
- Added deterministic adjacent artifact manifests containing compiler/toolchain/
  runtime ABI versions, actual allocated names, ordered typed inputs, result type,
  and feature metadata.
- Added native-Lean versus Node differentials for every staged literal and scalar
  primitive through `RxExpr → Reactive IR → JsAst → ESM`, with discriminating
  comparison/modulo cases, hostile identifiers and text, values above 2^53, and
  both printer modes. The Expression Playground now executes this same public
  path and validates its manifests.
- Review found and permanently regressed signed-divisor modulo normalization,
  `String` shadowing, strict-ESM reserved bindings, shallow AST scope validation,
  incompatible IR input reuse, incomplete Core-to-IR coverage, and missing
  artifact metadata.
- Verified `b2720a1` in the workspace and a fresh no-hardlinks clone with
  `./scripts/check.sh`; 106 build jobs, 576 public theorems, 146 exact reviewed
  axiom uses, 38 exact generated unsafe recursion helpers, 40 seeded graph cases,
  46 native/JavaScript cases across both printer modes, examples, negative and
  policy gates all passed, and both worktrees remained clean.
- Completed M4's explicit component/update/view model, typed surface declaration
  inventory, checked static DOM split, scoped component/JSX-like syntax, and
  source-linked diagnostics down to nested elements, interpolations, and events.
- Added deterministic component lowering through Reactive IR and validated
  JavaScript AST to direct DOM mount/event/sink functions. The tiny DOM/disposal
  hosts contain no dependency discovery or scheduler, and typed manifests record
  state slots, graph hash, counts, imports, exports, toolchain, and runtime ABI.
- Added pure `check`, JSON/DOT `graph`, and atomic `build` CLI paths. ADR-0007
  records locked versioned sibling publication through one symlink rename;
  unmanaged outputs and hostile bundle/lock symlinks fail without mutation.
- Built Counter entirely through public APIs with four events, derived fan-out,
  direct scalar text sinks, generated hostile text, separate instances, and
  idempotent disposal. Chromium covers mount, updates, same-value write
  suppression, keyboard activation, isolation, disposal, hostile text, and axe.
- Review permanently regressed decorative surface roles, generic cycle errors,
  missing nested spans, click-only generic elements, shallow CLI checks,
  incomplete DOT, untyped manifests, non-atomic directory replacement, and
  symlink-following cleanup/lock hazards.
- Verified `246619c` in the workspace and a fresh no-hardlinks clone with
  `./scripts/check.sh`; 138 build jobs, 727 public theorems, 184 exact reviewed
  axiom uses, 53 exact generated unsafe helpers, 40 seeded graph cases, 46
  native/JavaScript cases in both printer modes, four Chromium tests, examples,
  negative and policy gates all passed, and both worktrees remained clean.
- Completed M5's generated outermost transaction boundary, transaction-local
  sequential writes, final lawful source comparison, rank-ordered affected
  derived phase, equality stopping, separate sink/cache phase, and synchronous
  nested dispatch with cycle rejection.
- Added ABI-2 copied instrumentation snapshots with commit/source-write/derived/
  sink/DOM counters and stable trace names. Consumer mutation cannot reach
  private transaction control; canceled source writes and equal-output sinks have
  dedicated Chromium regressions.
- Added checked direct/effective transitive event summaries and a source-linked
  `LRX-TYPE-108` derived-read rejection that names the future transaction barrier.
- Added the public Diamond Lab, generated native-reference artifact, deterministic
  module/manifests, and browser assertions that all derived nodes finish before
  sinks and the fan-in text observes only the final parents.
- Proved nested source-write application equals ordered flattening and specialized
  optimized/reference equivalence to the flattened list. ADR-0005 records the
  exact theorem footprints and explicitly excludes JavaScript depth/commit claims.
- Added a correctness-gated 1,000-update small-diamond smoke harness. ADR-0009
  reserves the complete size/build/mount/update/DOM/memory benchmark report for M10.
- Verified `f20c2c5` in the workspace and a fresh no-hardlinks clone with
  `./scripts/check.sh`; 142 build jobs, 742 public theorems, 189 exact reviewed
  axiom uses, 55 exact generated unsafe helpers, 40 property cases, 46 native/JS
  cases in both printer modes, deterministic Counter/Diamond artifacts, seven
  Chromium tests, benchmark smoke, examples, negative and policy gates all passed.
- Completed M6's sealed `Vector α n`/`Fin n` runtime identities, indexed native
  semantics, safe staged vector access, Reactive IR proof-erasure report/assertion,
  and the named `erasureReport_no_inspections` theorem with exact `[propext]`
  footprint.
- Added immutable typed props and definitionally typed event parameters. Dependent
  Tabs privately stores `Fin (n + 1)`, accepts equal nonempty label/panel vectors,
  and requires an explicit `Nat` plus strict-bound proof for nonzero initial
  selection. ADR-0011 records pinned Lean's modulo-normalized raw `Fin` literals.
- Added ABI 3, typed dependent manifests, direct array-index lowering, strict
  source equality, panel sink caching, copied instrumentation, and finite private
  event handlers. Only `mount` is exported; generated values contain no proof
  objects or Lean runtime.
- Built Dependent Tabs entirely through public APIs. Deterministic artifacts and
  Chromium cover initial/every-tab selection, native-button keyboard activation,
  maintained grouped `aria-pressed` state, hostile name/label/panel text, active
  reselection suppression, equal-panel sink caching, axe, and instrumentation.
- Added four dependent compile-fail contracts for mismatched lengths, empty tabs,
  invalid unchecked selection, and arbitrary `Nat` indexing. Native-to-Node vector
  cases derive first/middle/last expectations from `RxExpr.eval` in both printers.
- Strengthened the benchmark gate to record four reference evaluations versus one
  optimized evaluation for the parity actual-change case, while retaining ADR-0009's
  non-comparative timing scope. IR and Lower are now in the pure-path safety gate.
- Verified `f6317cd` in the workspace and a fresh no-hardlinks clone after
  `corepack pnpm install --frozen-lockfile --ignore-scripts`, both with
  `./scripts/check.sh`: 156 Lean jobs, 836 public theorems, 209 exact reviewed
  axiom uses, 64 exact generated unsafe helpers, 40 seeded graph cases, 49
  native/JavaScript cases in both printer modes, deterministic Counter/Diamond/
  Dependent Tabs artifacts, nine Chromium tests, measured work suppression,
  compile-fail, placeholder, axiom, and 39-file semantic-safety gates passed.
- Completed M7's pure total parser/validator combinators, sealed nonempty/bounded/
  accepted refinements, private `ValidatedForm` and fake-submit capabilities,
  typed DOM properties, and closed input/change/checked/submit/key/focus payloads.
- Added a shared typed form-lowering boundary so production emitters select host
  listeners and property names only from sealed capabilities. Private
  state-control and Temperature update-plan construction is compile-fail gated.
- Built Temperature Converter with explicit raw/active-scale/conditional-converted
  source writes, a cycle-free checked graph, strict native/BigInt ASCII grammar,
  truncating negative conversion, controlled cursor preservation, deterministic
  invalid observations, complete accessibility state, and hostile-text safety.
- Built Validated Form with input-synchronized submit-authoritative state,
  dependency-filtered validation sinks, accessible unique IDs/errors, checked and
  disabled properties, prevented submit, stale-valid rejection, and a typed fake
  command boundary. Text change remains a typed observational adapter.
- Review permanently regressed Lean-only numeric separators, undeclared cross-field
  writes, decorative DOM capabilities, repurposed instrumentation counters, raw
  key retention, incomplete invalid-state accessibility, hidden last-event state,
  no-blur stale submission, and reference-style unrelated sink evaluation.
- Verified `51a412a` in the workspace and the no-hardlinks clone at
  `/private/tmp/leanrx-m7-clean.EsG3v5`, both with `./scripts/check.sh`: 184 Lean
  jobs, 897 public theorems, 220 exact reviewed axiom uses, 64 exact generated
  unsafe helpers, 40 seeded graph cases, 49 native/JavaScript cases in both
  printer modes, deterministic five-application artifacts, twelve Chromium tests,
  benchmark, compile-fail, 114-file placeholder, and 49-file semantic-safety gates
  passed; the clone remained clean.
- Completed M8's sealed conditional, positional, keyed, and owned local-region
  reference models. Reconciliation consumes only private-constructor reachable
  state with internal fresh-token counters; public callers cannot forge duplicate
  current entries or stale allocation state.
- Added a tiny explicit local-region host with fail-before-mutation duplicate-key
  checks, retained keyed identity, scoped structural ownership, copied metrics,
  and idempotent disposal. Static scalar sinks remain direct writes; no root-wide
  Virtual DOM, dependency discovery, or runtime scheduler was introduced.
- Built TodoMVC through public APIs with a closed pure update algebra, canonical
  native logical-DOM oracle, typed delegated actions, manifest-only dynamic layout
  metadata, deterministic generated artifacts, and explicit reference propagation.
- Chromium permanently covers hostile titles, populated accessibility, every
  filter, keyed reorder/focus/routing, conditional edit/view replacement,
  clear-during-edit draft retention, adversarial toggle events, exact work counts,
  post-disposal suppression, and logical agreement with the native oracle.
- Review permanently regressed forged reconciliation state, native/generated draft
  drift, graph-equality leakage from record/list metadata, unscoped Enter/Escape,
  unlabeled checkboxes, click-only spans, browser-payload-dependent toggle semantics,
  and incomplete nested-write instrumentation.
- Verified `7b7ecae` from the workspace and the no-hardlinks clone at
  `/private/tmp/leanrx-m8-clean.dj1gDm/repo`, both with `./scripts/check.sh`: 204
  Lean jobs, 1043 public theorems, 241 exact reviewed axiom uses, 71 exact generated
  unsafe helpers, 40 seeded graph cases, 49 native/JavaScript cases in both printer
  modes, deterministic six-application artifacts, local-region host checks, fourteen
  Chromium tests, benchmark, compile-fail, 127-file placeholder, and 56-file
  semantic-safety gates passed; the clone remained clean.
- Completed M9's typed commands and ordered batches, opaque cancellation handles,
  explicit resource ownership, stale-result rejection lemmas, deterministic native
  mocks, injected timer/storage/HTTP/foreign adapters, and ABI-6 copied effect
  instrumentation.
- Added indexed port representation evidence and nominal structured wire types
  without weakening the closed reactive runtime/equality ABI. Generated manifests
  name exact input/output records, host imports, error codes, ownership features,
  and versioned runtime contracts.
- Built Notes and Issue Browser entirely through public APIs. Notes exercises
  restore, debounced replacement, persistence errors, late-result suppression,
  ordered cancellation, and disposal. Issue Browser exercises encoded queries,
  retry, pagination, keyed append, non-200/decoder failures, replacement, stale
  delivery suppression, and abort-on-disposal.
- Hardened the effect host against same-handle replacement, reentrant/throwing/
  rejected cancellation, hostile rejection values, blocked storage acquisition,
  throwing delivery, throwing timer setup, and synchronous/rejected foreign ports.
  Ownership is removed before cleanup and every base disposer still runs once.
- Added exact native/JavaScript Issue decoder agreement for integer JSON lexemes,
  safe-ID bounds, fractional rounding cases, same-page/cross-page uniqueness, and
  pagination BigInts. Both sides reject exponent magnitudes above 16 before the
  general JSON parser, preventing the reviewed Lean exponentiation panic/DoS path.
- Review permanently regressed shared Notes lifecycle errors, cancel-before-render
  ordering, false port manifests, unsafe IDs, duplicate keyed issues, stale numeric
  handle completion, orphaned reentrant replacement, partial cleanup, lossy JSON
  numbers, throwing Web Storage getters, missing delivery evidence, and unbounded
  zero exponents.
- Verified `26b362e` in the workspace and the fresh no-hardlinks clone at
  `/private/tmp/leanrx-m9-exact.mYFds7/repo`, both with `./scripts/check.sh`: 230
  Lean jobs, 1199 public theorems, 283 exact reviewed axiom uses, 76 exact generated
  unsafe helpers, 40 seeded graph cases, 49 native/JavaScript cases in both printer
  modes, deterministic eight-application artifacts, region/effect host checks,
  sixteen Chromium tests, benchmark, compile-fail, 146-file placeholder, and
  67-file semantic-safety gates passed; the clone remained clean.
- Completed M10's closed `ListDelta` vocabulary, total checked application,
  proof-carrying `PlannedDeltas`, full-recomputation reference, explicit delta,
  and configurable pure hybrid cost model. Reset targets use the architecture's
  `Array` representation and any reset-bearing batch is classified visibly.
- Sealed Grid state/spec/checked construction and built the public 10,000-row
  Data Grid through a fixed checked browser cost model. Full/delta/hybrid run the
  same seven actions from the empty state; the native oracle and Chromium compare
  every one of the 5,000 final keys, texts, positions, and selection bits.
- Added ABI-7 whole-batch structural validation, fail-before-mutation fake-DOM
  coverage, exact manifest/runtime representation checks, copied standard/region/
  Grid instrumentation, deterministic artifacts, hostile-text safety, named
  read-only table semantics, native controls, keyboard, axe, and disposal tests.
- Review permanently regressed reverse-as-sort, unlowered public cost parameters,
  same-key swap corruption, invalid action-order crashes, a nonempty generated
  initial state, endpoint-only oracle comparison, false instrumentation labels,
  strategy representation drift, retained listener closures, and incomplete
  delta-validation branches.
- Measured native latency/model work, six position-balanced Chromium operation
  latency, sampled V8 allocations, process heap observations, exact generated
  work, artifact size, clean build/generation cost, and API complexity. ADR-0017
  keeps structural delta opt-in: retained row work falls for small keyed changes,
  but emitted DOM writes are identical and native trace time is effectively tied.
- Verified `d445bfe` in the workspace and a fresh no-hardlinks clone with
  `./scripts/check.sh`: 246 Lean jobs, 1365 public theorems, 304 exact reviewed
  axiom uses, 77 exact generated unsafe helpers, 40 seeded graph cases, 49
  native/JavaScript cases in both printer modes, deterministic nine-application
  artifacts, region/effect host checks, sixteen standard plus one Grid Chromium
  test, both benchmarks, 37 compile-fail fixtures plus four focused diagnostic
  checks, 158-file placeholder, and 73-file semantic-safety gates passed; both
  checkouts remained clean.
- Added deterministic self-contained accessible HTML graph artifacts alongside
  JSON/DOT, including hostile-metadata escaping, script exclusion, exact CLI/build
  equality, and native/browser accessibility regressions.
- Added an explicit learnability CLI registry with clearer pure `check`, atomic
  `build`, JSON/DOT/HTML `graph`, `scaffold`, `explain`, and fail-closed `doctor`.
  Doctor enforces Node 22+, exact pnpm 10.33.0 and Playwright 1.62.1, installed
  Chromium, exact toolchain/runtime hosts, and backend smoke; incompatible PATH
  fixtures and unmanaged output failures are permanent regressions.
- Added compile-checked editor declaration aliases and a compile-executed public
  language-guide component covering both explicit and scoped surface APIs.
- Published the language, tooling, architecture, backend support, trust,
  accessibility, and dogfood case-study guides, linked to the existing
  performance, internals, ADR, and Lean-upgrade references. Documentation
  distinguishes named kernel theorems from pure checks, executable evidence,
  measurements, and the remaining JavaScript/browser/platform TCB.
- Built the seven-page LeanRx documentation site entirely through public
  component APIs. One page source drives three derived page values and three text
  sinks; seven native buttons cover introduction, Counter, graph, dependent Tabs,
  effects/resources, limitations, and an inert Counter graph. The atomic bundle
  includes its deterministic manifest, graph data/DOT/HTML viewer, editor aliases,
  production shell, stylesheet, and two tiny hosts.
- Recorded self-hosting limitations rather than hiding them behind another
  framework: no URL/history router, semantic navigation/link/code/list vocabulary,
  typed CSS, general VDOM, arbitrary Lean compiler, raw HTML/URL context, SSR,
  hydration, or formal JavaScript/DOM proof.
- Verified `d9c85ab` with the complete `./scripts/check.sh` from a new
  no-hardlinks clone: 254 Lean jobs, 1376 public
  theorems, 307 exact reviewed axiom uses, 77 exact generated unsafe helpers, 40
  seeded graph cases, 49 native/JavaScript cases in both printer modes,
  deterministic ten-application artifacts, region/effect and CLI negative gates,
  eighteen standard plus one Grid Chromium test, both benchmarks, 37
  compile-fail fixtures plus four focused diagnostic checks, 163-file placeholder,
  and 76-file semantic-safety gates passed. The clone and source workspace
  remained clean.
- Made the shipped runtime faster without touching the checked Lean models
  (ADR-0018, runtime ABI 8): the keyed region and the delta region's full
  reconcile now trim the unchanged prefix/suffix and move only the retained
  nodes outside one longest order-preserving subsequence (a swap is two DOM
  moves instead of a near-full sibling walk), a fully owned parent is cleared
  with one bulk removal, the DOM host gained `cloneTemplate`/`firstChild`/
  `nextSibling` so the js-framework-benchmark rows are deep-cloned from one
  static template, and delegated keys resolve from the nearest keyed
  ancestor. Fake-DOM placement/bulk-clear/fuzz tests, the updated Grid
  placement snapshot (15,000 for every strategy), and `BENCHMARK.md` record
  the change; the pure region theorems are unchanged and still do not cover
  the host placement algorithm.
- Made the shipped runtime faster and smaller again without touching the
  checked Lean models (ADR-0019, runtime ABI 9): the DOM host's
  `cloneTemplate` clones a node that `mount` builds once and `setKey` records a
  delegated key as a node property that `listenDelegated` resolves alongside
  `data-lrx-key` attributes; the keyed region validates through its key index
  alone (retained keys matched by position first, repeated keys rolled back
  before any callback) and rebuilds a region that owns its whole connected
  parent with one bulk clear and one detached bulk insertion; the opt-in
  structural-delta adapter moved to `runtime/leanrx_delta_region.mjs`, which
  only the Data Grid imports. Fake-DOM tests lock the detach/restore, focus,
  foreign-sibling, and empty-region duplicate-key cases; the js-framework-
  benchmark headless run recorded in `BENCHMARK.md` measured create 10,000
  345.7 → 335.5 ms, select 8.2 → 7.5 ms (level with Solid), and 27.6 → 23.5 KB
  shipped (6.8 → 6.3 KB Brotli) with every other workload improved or level.
- Made the shipped runtime faster again without touching the checked Lean
  models (ADR-0020, runtime ABI 10): both keyed regions forward the per-update
  context to their mount/update/dispose callbacks, the keyed region gained
  `updateAt` (one retained row, key-checked) and registers keys added to an
  empty region with one index insertion, and the conditional/positional
  regions moved to `runtime/leanrx_unkeyed_region.mjs`, which only TodoMVC
  imports. The js-framework-benchmark backend commits the model rows as the
  keyed items (no per-commit projection array) and lowers `select` to two
  `updateAt` calls. Fake-DOM tests lock context forwarding, `updateAt`, and
  empty-region duplicate rejection; the headless run recorded in
  `BENCHMARK.md` measured select 7.5 → 6.2 ms (below Solid), replace 35.1 →
  33.7 ms, create 10,000 335.5 → 330.0 ms, swap 23.5 → 22.8 ms, clear 14.9 →
  14.4 ms, and 23.5 → 22.7 KB shipped, with the other workloads level within
  noise.
- Made the shipped runtime smaller again without touching the checked Lean
  models (ADR-0021, runtime ABI 11): the five typed control-event adapters
  (`listenValue`, `listenChecked`, `listenKey`, `listenFocus`, `listenSubmit`)
  moved unchanged from the DOM host into `runtime/leanrx_form_events.mjs`,
  which only the form backends (Temperature, Validated Form, Notes, TodoMVC,
  Issue Browser) import; delegated-only artifacts (Data Grid, the
  js-framework-benchmark) ship 1,214 fewer raw bytes (benchmark baseline
  23,261 → 22,047 raw, 6,506 → 6,422 Brotli). The browser gates, artifact
  checks, codegen gate, and doctor cover the split; the headless run recorded
  in `BENCHMARK.md` measured 22.7 → 21.5 KB shipped (6.4 → 6.3 KB Brotli)
  with byte-identical generated and region code, so the CPU rows moved only
  by run-to-run drift (append 38.5 → 36.4 ms, partial update 20.9 → 19.8 ms,
  swap's mean 22.8 → 26.9 ms from one 62.8 ms sample with a 23.9 ms median).
- Made the shipped runtime smaller a third time without touching the checked
  Lean models (ADR-0022, runtime ABI 12): `makeDisposer` moved unchanged from
  `runtime/leanrx_host.mjs` (deleted; 867 bytes, served uncompressed by the
  upstream server's 1 KiB Brotli threshold) into the DOM host every artifact
  already fetches, and the keyed region and DOM hosts' multi-line comments
  were condensed to the terse style of the other hosts with the contract prose
  moved to `docs/internals/runtime-representation.md`; every artifact fetches
  one module fewer and the benchmark baseline moves 22,047 → 20,684 raw,
  6,422 → 5,415 Brotli. The headless run recorded in `BENCHMARK.md` measured
  21.5 → 20.2 KB shipped (6.3 → 5.3 KB Brotli) and first paint 73.5 → 74.5 ms
  against Solid's 79.0 ms, with the CPU rows moving only by run-to-run drift
  (swap's mean 26.9 → 23.6 ms because this run had no outlier sample; every
  CPU row at or below Solid).
- Made the shipped js-framework-benchmark application smaller a fourth time
  without touching the checked Lean models or the runtime ABI (ADR-0023):
  `lake exe leanrx_js_framework_benchmark` now flattens the page into one
  `main.mjs` — the DOM host and keyed region host inlined from `runtime/` in
  import order with comments, blank lines, indentation, and `export` dropped,
  then the generated declarations without import/export statements, then the
  mount statement — so the page fetches two files instead of five; nothing is
  tree-shaken or renamed and no minifier is added (esbuild's bundle-and-minify
  would reach about 3.1 KB Brotli and remains undecided). The benchmark gate
  syntax-checks and runs the flattened module and the baseline moves 20,684 →
  17,480 raw, 5,415 → 4,277 Brotli (`main.mjs` alone 15,814 / 3,917 bytes
  against Solid's 11,563 / 4,358). The headless run recorded in
  `BENCHMARK.md` measured 20.2 → 17.1 KB shipped (5.3 → 4.2 KB Brotli, now
  below Solid's 4.5 KB) and first paint 77.6 ms against Solid's 81.3 ms, with
  the CPU rows moving only by run-to-run drift (swap 23.6 → 21.2 ms, remove
  17.9 → 18.2 ms against Solid's 18.0 ms within a ±2.2 ms spread; every other
  CPU row below Solid).
- Made the shipped js-framework-benchmark application smaller a fifth time
  without touching the checked Lean models or the runtime ABI (ADR-0024):
  `LeanRx/Backend/JsCompact.lean` is a dependency-free, fail-closed
  JavaScript compactor (tokenizer, whitespace-minimal printing, `x["name"]`
  → `x.name`, top-level and per-function short identifiers) that the
  benchmark build runs over the flattened module; it rejects every construct
  it does not model (`LRX-BE-031`) and is covered by a golden/rejection test,
  `node --check`, and the Playwright contract tests. The baseline moves
  17,480 → 9,788 raw, 4,277 → 3,247 Brotli (`main.mjs` alone 8,122 / 2,887
  bytes against Solid's 11,563 / 4,358), below Solid on both measures. The
  headless run recorded in `BENCHMARK.md` measured 17.1 → 9.6 KB shipped
  (4.2 → 3.2 KB Brotli against Solid's 11.5 / 4.5 KB) and first paint 77.8
  ms against Solid's 81.5 ms, with the CPU rows moving only by run-to-run
  drift (swap 21.2 → 24.6 ms against Solid's 23.7 ms, within one standard
  deviation, LeanRx's script phase half of Solid's; every other CPU row
  below Solid).
- Made the shipped js-framework-benchmark application smaller a sixth time
  without touching the checked Lean models or the runtime ABI (ADR-0025):
  the JavaScript AST printer emits parentheses only where operator
  precedence requires them and prints `x = x + e` as `x += e` (every
  generated artifact, both printer modes; covered by the differential suite
  and the example contracts), and the benchmark backend omits the
  `return null` statements from handlers whose results nothing reads. The
  baseline moves 9,788 → 9,341 raw, 3,247 → 3,217 Brotli (`main.mjs` alone
  7,675 / 2,857 bytes against Solid's 11,563 / 4,358). The headless run
  recorded in `BENCHMARK.md` measured 9.6 → 9.1 KB shipped (3.2 → 3.1 KB
  Brotli against Solid's 11.5 / 4.5 KB) with every CPU row below Solid's
  (swap 24.6 → 23.2 ms against Solid's 25.5 ms, still within one standard
  deviation; append 37.8 → 36.8 against 38.6) and the single-sample first
  paint at 81.3 ms against Solid's 76.8 ms (77.8 against 81.5 in the
  previous run; the row does not separate the two).
- Made swapping and removing rows cheaper without touching the checked Lean
  models (ADR-0026, runtime ABI 13), after a paired local measurement against
  upstream vanilla showed the remaining create/append gap to be the id
  representation and per-row markup rather than the key index (which the
  duplicate-key contract requires) and a swap's two DOM moves to be the floor
  (`Node.moveBefore` measures the same): the keyed region gains `swapAt`
  (two moves, one when adjacent, update callbacks for exactly the two
  positions) and `removeAt` (one disposal, later rows shift without a
  callback), both validating keys before any callback or DOM mutation, and
  the benchmark backend lowers `swaprows` and `remove` through them instead
  of reconciling every row. Locally (warm, unthrottled) swap script falls
  0.14 → 0.05 ms (vanilla 0.04) and remove 0.19 → 0.085 ms (vanilla 0.12); a
  focused upstream A/B (4×/2× CPU slowdown, vanilla as drift control)
  measured swap script 1.31 → 0.51 ms and remove 0.43 → 0.24 ms. The fake-DOM
  suite locks both operations; the baseline moves 9,341 → 10,087 raw,
  3,217 → 3,449 Brotli (`main.mjs` alone 8,421 / 3,089 bytes against Solid's
  11,563 / 4,358). The headless run recorded in `BENCHMARK.md` measured swap
  23.2 → 20.3 ms (script 0.99 → 0.40) against Solid's 23.5 ms and remove
  17.8 → 16.9 ms against 17.6, the other CPU rows moving with Solid by drift
  and every CPU row below Solid's, at 9.9 KB shipped (3.4 KB Brotli against
  Solid's 11.5 / 4.5 KB).
- Validated monotone keys without the key index in the keyed region
  (ADR-0027, runtime ABI unchanged) after a CDP sampling profile of the
  create-10,000 click put the index at 0.8 ms of the 2.2 ms script gap to
  upstream vanilla (the rest: garbage-collection volume, the per-row action
  attributes in the cloned template, and the BigInt id rendering): keys that
  are all numbers, all bigints, or all strings and strictly increasing or
  decreasing are pairwise distinct (`<` totally orders each type but is not
  transitive across number and string keys, so mixed types never qualify),
  the index is built from the previous rows only when a retained key is found
  away from its position, and it is dropped when nothing is retained, so the
  benchmark's id-ordered creates and appends never hash a key and the
  duplicate-key contract is unchanged. A deterministic fuzz over number,
  bigint, string, mixed, symbol, and object keys with repeated keys injected
  at arbitrary positions and a differential fuzz against the previous host
  (32,000 operations, no difference) lock the behavior. Locally (paired, 12
  clicks per page, 10 rounds) create 10,000 falls 0.9 ms and create 1,000 and
  replace about 0.1 ms; the baseline moves 10,087 → 10,380 raw, 3,449 → 3,540
  Brotli (`main.mjs` alone 8,714 / 3,180 bytes). The headless run recorded in
  `BENCHMARK.md` measured create 10,000 script 28.1 → 27.4 ms (Solid 34.6 →
  36.7) for 325.0 → 323.1 ms total against Solid's 362.8 in a run that
  drifted slower for every framework, every CPU row still below Solid's, at
  10.1 KB shipped (3.5 KB Brotli against Solid's 11.5 / 4.5 KB).
- Reached a cloned row template's text slots without wrapping the elements
  between them (ADR-0028, runtime ABI 14) after a paired CDP profile showed
  the remaining create-10,000 script gap to upstream vanilla to be
  garbage-collection volume that both sides spend on DOM wrappers (six per
  row: the `tr`, two cells, the link, and two texts, all retained while in
  the document): the DOM host gains `nextText(node)` — the Text node that
  follows a node in document order through one shared
  `TreeWalker(SHOW_TEXT)`, documented as not stopping at the node's subtree —
  and the benchmark backend mounts a row with two `nextText` calls instead of
  four `firstChild`/`nextSibling` reads, so a row allocates three wrappers and
  makes six binding calls instead of eight; the Lean model and the region
  host are unchanged. A per-row walker (+1.0 ms) and a stateful walker API
  (same speed) were measured and not adopted, and a swap's two DOM moves
  were re-checked as the floor for a keyed exchange. The counter browser
  suite locks `nextText` on real DOM (slot order, identity, `null` off a
  detached subtree, comment skipping, and the escape past a subtree without
  text). Locally (paired, 12 clicks per page, 10 rounds) create 10,000 falls
  1.24 ms and is level with vanilla, create 1,000 0.12 ms, replace 0.08 ms;
  the baseline moves 10,380 → 10,486 raw, 3,540 → 3,585 Brotli (`main.mjs`
  alone 8,820 / 3,225 bytes). The headless run recorded in `BENCHMARK.md`
  measured create 10,000 script 27.4 → 24.9 ms (Solid 36.7 → 35.5), create
  1,000 script 2.7 → 2.5, replace 5.4 → 5.3, and append 3.0 → 2.9, memory
  after adding 1,000 rows 2.01 → 1.97 MB, the totals moving with paint drift
  and every CPU row except a coin-flip partial update (20.9 against 20.7)
  below Solid's, at 10.2 KB shipped (3.5 KB Brotli against Solid's 11.5 /
  4.5 KB).

## In progress

- None. The planned M0–M11 implementation is complete.

## Next

- No next milestone is authorized by `PLAN.md`. A release would first require a
  selected license, package/public compatibility policy, and explicit release
  criteria; the current repository remains an unreleased experiment.

## Known blockers

- None for the M0–M11 plan. Release prerequisites above remain intentionally
  unresolved and are not hidden by the implementation status.

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

## M2 independent review notes

- Lean/toolchain: PASS at `c1c071d`; explicit affected traces, optimized-only
  repeated-state validity, typed bridge invariants, graph-first cycle diagnostics,
  and extra property seeds were verified.
- Type theory/proof: PASS; `wellFormed_of_check`, reference initialization,
  exact changed-frontier preservation, central store/observation equivalence, and
  optimized next-state validity are kernel checked with exact audited footprints.
- Compiler/backend: PASS; graph/proof data derive from the same staged expressions,
  planned constructors are private, equality/source/sink shapes are sealed, and
  unsupported forward proof-subset dependencies fail loudly.
- Frontend/runtime: PASS; hostile graph text remains escaped data, Graph Lab uses
  the single-declaration public path, CI commands match locally, and no premature
  DOM/browser/runtime implementation exists.
- Test/quality: PASS after workspace and fresh-clone gates; all required graph
  shapes, no-consumer and canceled transactions, branch-complete diagnostics,
  source spans, replayable properties, deterministic artifacts, dogfood assertions,
  and all 15 M2 commit trailers were independently checked.

## M3 independent review notes

- Lean/toolchain: PASS at `b2720a1`; strict ESM identifiers, typed input ABI,
  private emitted artifacts, exact policy audits, staged primitive coverage, and
  both printer modes were verified.
- Type theory/proof: PASS; typed lowering remains exhaustive and fail-closed, no
  arbitrary Lean compiler IR or banned declarations entered the backend, and
  JavaScript execution remains explicitly inside the trusted computing base.
- Compiler/backend: PASS; AST scope validation, global protection, runtime
  signatures, discriminating full-pipeline differentials, deterministic manifests,
  and source-linked unsupported diagnostics satisfy the M3 contract.
- Frontend/runtime: PASS; hostile names/text, dynamic-code bans, BigInt semantics,
  both output modes, and a separate generated-artifact scan passed, with no
  premature DOM/browser runtime introduced.
- Test/quality: PASS after workspace and fresh-clone gates; all 11 M3 commits are
  coherent and bisectable with exactly one required assistance trailer.

## M4 independent review notes

- Lean/toolchain: PASS at `1bb3834`; typed surface alignment, exact nested/root
  spans, diagnostic taxonomy, audited CLI driver, and symlink-safe atomic output
  passed the full gate.
- Type theory/proof: PASS; component/backend/browser behavior remains explicitly
  in the TCB, the isolated elaborator evaluation is exact-name audited, and no
  semantic path gained unsafe, partial, or unreviewed axioms.
- Compiler/backend: PASS at `1bb3834`; graph metadata and diagnostics are complete,
  manifests are typed, CLI checks every pure backend phase, publication is atomic,
  and compiler/host responsibilities remain separated.
- Frontend/runtime: PASS; generated hostile text, native-button click semantics,
  direct text writes, work suppression, instance isolation, disposal, keyboard,
  axe, pinned dependencies, and tiny-host boundaries passed in Chromium.
- Test/quality: PASS after workspace and fresh-clone suites; rollback, stale-file,
  hostile symlink/lock, JSON/DOT, codegen determinism, public dogfood, browser,
  negative, policy, and commit-trailer checks are permanent gates.

## M5 independent review notes

- Lean/toolchain: PASS at `f20c2c5`; copied instrumentation, ABI 2, effective event
  summaries, honest theorem naming, dispatch/derived-read diagnostics, and the
  full gate were verified.
- Type theory/proof: PASS; `apply_eq_flatten` is axiom-free, the three named nested
  lemmas have exact reviewed `[propext, Quot.sound]` footprints, and generated
  event evaluation/commit counts remain executable TCB evidence.
- Compiler/backend: PASS; final-source equality, rank-ordered affected closure,
  sink-cache suppression, immutable instrumentation access, deterministic
  manifests/artifacts, and host separation all passed adversarial review.
- Frontend/runtime: PASS; multi-write/nested batching, canceled source, equal sink,
  Diamond phase order/glitch freedom, keyboard, axe, hostile text, isolation, and
  disposal passed seven Chromium tests.
- Test/quality: PASS after workspace and fresh-clone suites; ADR-0009 prevents the
  smoke harness from being reported as a complete benchmark. History exception:
  `3645aba` introduced checked `Update.dispatch` one commit before `efd4844`
  implemented its lowering, so that intermediate commit was buildable but not a
  behavior-complete public capability. The history is preserved rather than
  rewritten; later public constructors and lowering must land together.

## M6 independent review notes

- Lean/toolchain: PASS at `f6317cd`; sealed dependent representations, explicit
  finite construction, actual-change Tabs semantics, native-derived vector
  differentials, measured suppression, and all local gates were verified.
- Type theory/proof: PASS; the closed-IR erasure theorem has exact `[propext]`,
  vector dependency congruence retains `[propext, Quot.sound]`, IR/Lower totality
  is policy-gated, and JavaScript/browser erasure remains explicitly in the TCB.
- Compiler/backend: PASS; the Core → Reactive IR → erasure assertion → typed
  JavaScript AST path is intact, ABI 3 is deterministic, finite handlers are
  private, equality/cache suppression is correct, and the host stays integration-only.
- Frontend/runtime: PASS; active reselection and equal-output caching, copied
  instrumentation, hostile dependent text, grouped maintained selection state,
  keyboard, axe, disposal boundaries, and supply-chain pins passed Chromium review.
- Test/quality: PASS after workspace and fresh no-hardlinks suites; 15 coherent M6
  commits each contain exactly one required assistance trailer. ADR-0011 records
  the false raw-`Fin` literal assumption, and ADR-0012 resolves the M0–M6 versus M7
  dogfood-order contradiction without weakening later form requirements.

## M7 independent review notes

- Lean/toolchain: PASS at `51a412a`; sealed form/update capabilities, strict
  numeric grammar, explicit active-scale state, input-authoritative submission,
  diagnostics, exact policy audit, and all local gates were verified.
- Type theory/proof: PASS; refinements and command construction remain sealed,
  form parsing is pure/total, the complete checked store determines Temperature
  observations, and generated validation/JavaScript/browser behavior remains
  explicitly executable TCB evidence rather than a formal theorem.
- Compiler/backend: PASS; typed form constructors drive host lowering, effective
  write sets and graph sinks are explicit, manifests/counters keep their ABI
  meanings, affected validation sinks follow declared dependencies, and no-blur
  invalid submission fails closed.
- Frontend/runtime: PASS; controlled cursor/raw text, simultaneous invalid fields,
  convergent event histories, exact input/change/checked payloads, prevented and
  stale-submit rejection, accessibility state, isolation, disposal, hostile text,
  and axe passed twelve Chromium tests.
- Test/quality: PASS after workspace and fresh no-hardlinks suites; native/browser
  grammar and messages, truncating negative division, source-linked diagnostics,
  state-complete observations, exact sink work, and private-constructor negatives
  are permanently regressed. History note: `e407ce9` fixed validator messages
  before the distinguishing lexical/upper-bound browser fixtures landed; history
  is preserved rather than rewritten.

## M8 independent review notes

- Lean/toolchain: PASS at `7b7ecae`; reachable private reconciliation state,
  manifest/runtime type separation, exhaustive closed Todo actions, exact write
  instrumentation, native logical oracle, and the full clean-clone gate were verified.
- Type theory/proof: PASS; conditional projection is axiom-free, positional/keyed
  projection use only exact reviewed `[propext]`, and browser identity/disposal,
  specialized extraction, JavaScript, and DOM remain explicitly inside the TCB.
- Compiler/backend: PASS; lowering consumes compiler-owned action tags, pure and
  generated Todo semantics agree, artifacts are deterministic, the region host is
  local and non-scheduling, and reference propagation is named without an
  actual-change claim.
- Frontend/runtime: PASS; hostile text, populated axe, native-control keyboard
  routing, keyed identity/focus, branch and row disposal, filter/reorder routing,
  copied metrics, isolation, and post-disposal behavior passed fourteen Chromium
  tests.
- Test/quality: PASS after workspace and fresh no-hardlinks suites; all/active/
  completed views, canonical logical-DOM comparison, retained drafts, adversarial
  toggle payloads, forged-result compile failures, exact instrumentation, and
  deterministic artifacts are permanent regressions.

## M9 independent review notes

- Lean/toolchain: PASS at `26b362e`; indexed port evidence, private resource
  handles, reentrant replacement ownership, exact-number grammar, native/JS
  decoder matrices, and every local policy gate were verified.
- Type theory/proof: PASS; stale-result/resource lemmas retain their exact reviewed
  `[propext]` footprints, pure effect state remains total, the bounded native JSON
  pre-parser prevents the former panic path, and browser/foreign behavior remains
  explicitly inside the trusted computing base.
- Compiler/backend: PASS; manifests match the actual `HttpResponse → IssuePage`
  boundary, command interpretation follows update/render, generation is
  deterministic, pagination uses BigInt, and replacement/delivery/cancellation
  paths fail closed under adversarial inputs.
- Frontend/runtime: PASS; blocked storage, stale/reentrant work, cleanup failures,
  duplicate issues, hostile text, encoded queries, native-control keyboard paths,
  populated axe scans, copied metrics, and post-disposal suppression passed sixteen
  Chromium tests and focused fake-host probes.
- Test/quality: PASS after workspace and fresh no-hardlinks suites; exponent,
  fractional-rounding, safe-ID, uniqueness, delivery-901, timer-203, synchronous-
  402, replacement, cancellation, and unhandled-rejection branches are permanent
  regressions. All 21 M9 implementation commits have exactly one required
  assistance trailer and remain reviewable and bisectable.

## M10 independent review notes

- Lean/toolchain: PASS at `d445bfe`; sealed state/spec/planned-delta boundaries,
  exact ABI-7 metadata, full native/generated row agreement, fixed cost-model
  scope, reproducible measurements, exact policy gates, and history trailers were
  independently verified.
- Type theory/proof: PASS; `PlannedDeltas` target/reset laws and
  `Grid.plannedDeltas_correct` retain their exact disclosed footprints, while
  lowering, runtime identity, browser behavior, instrumentation, and performance
  stay explicitly inside executable evidence and the TCB.
- Compiler/backend: PASS; typed-JavaScript-AST lowering matches checked sort/swap/
  action/cost semantics, the manifest is exact, all 5,000 final rows match the
  native oracle, structural validation is atomic, and artifacts are deterministic.
- Frontend/runtime: PASS; the named read-only table, native/disabled controls,
  keyboard, hostile text, populated axe, invalid action ordering, copied metrics,
  batch validation, disposer ownership, and six rotated strategy runs passed.
- Test/quality: PASS after workspace and fresh no-hardlinks suites; exact logical/
  work snapshots, malformed deltas, six-position benchmark math, commands,
  limitations, negative conclusions, history bisectability, and the single exact
  assistance trailer on every M10 commit were independently checked.

## M11 independent review notes

- Lean/toolchain: PASS at `d9c85ab`; staged/native support claims, exact runtime
  prerequisites, explicit and scoped guide snippets, generated declarations,
  source policy, and the complete local gate were independently verified.
- Type theory/proof: PASS; graph HTML consumes sealed planned graphs, new tooling
  adds no semantic shortcut, exact theorem/axiom/unsafe audits remain green, and
  HTML/CLI/compiler/browser behavior stays executable TCB evidence rather than a
  formal claim.
- Compiler/backend: PASS; deterministic JSON/DOT/HTML graphs, explicit registry,
  version-aware doctor, normalized atomic errors, diagnostic explanations,
  editor aliases, docs lowering, manifest, artifacts, and host separation passed
  positive and adversarial checks.
- Frontend/runtime: PASS; all seven pages, hostile Limitations text, native
  keyboard controls, responsive shell, populated docs and standalone-viewer axe,
  exact work snapshot, mount isolation, disposal, script-free graph HTML, and
  pinned supply chain passed Chromium and static review.
- Test/quality: PASS after the exact `d9c85ab` full suite in a fresh no-hardlinks
  clone; all local Markdown links resolve, incompatible-tool
  shims and canonical guide compilation are effective regressions, history is
  conventional/bisectable, and every commit through the final audit has one exact
  assistance trailer.

## Commands

- `./scripts/check.sh`
- `./scripts/check_format.sh`
- `lake build`
- `lake exe leanrx_test`
- `lake exe leanrx_graph_properties -- 195936478`
- `lake exe leanrx_graph_lab`
- `./scripts/check_differential.sh`
- `./scripts/check_component_codegen.sh`
- `./scripts/check_region_runtime.sh`
- `./scripts/check_effect_runtime.sh`
- `./scripts/check_cli.sh`
- `./scripts/check_browser.sh`
- `./scripts/check_bench.sh`
- `./scripts/check_grid_bench.sh`
- `./scripts/check_examples.sh`
- `./scripts/check_compile_fail.sh`
- `./scripts/check_placeholders.sh`
- `./scripts/test_placeholder_scanner.sh`
- `./scripts/check_axioms.sh`
- `./scripts/check_semantic_safety.sh`
