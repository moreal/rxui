# LeanRx Implementation Plan for Codex

> Purpose: turn [`ARCHITECTURE.md`](./ARCHITECTURE.md) into a working, testable proof of concept
> Execution owner: Codex coding agent
> Working title: **LeanRx**
> Plan status: **Implementation contract**
> Last revised: 2026-08-19

## 0. Instruction to the coding agent

Implement the project described in `ARCHITECTURE.md` as a sequence of small, tested, reviewable commits.

Do not treat this document as an invitation to redesign the project while coding. When a genuine architectural contradiction appears:

1. reproduce it with the smallest example;
2. record the problem and alternatives in a new ADR;
3. choose the smallest change that preserves the research goal;
4. update `ARCHITECTURE.md`, `PLAN.md`, tests, and examples in the same commit;
5. continue implementation.

Do not ask the human to choose routine implementation details already resolved here. Escalate only decisions that fundamentally change the product thesis, license, trust boundary, or public language.

The implementation must remain usable after every commit. Do not create a long-lived broken branch or one giant “implement compiler” commit.

---

## 1. Mission

Build a Lean 4-hosted frontend framework/compiler PoC with:

- typed component state;
- pure derived expressions;
- atomic typed update programs;
- a static, dependency-indexed reactive graph;
- actual-change propagation in topological order;
- a full-recomputation reference semantics;
- a Lean correctness argument for the abstract propagation algorithm;
- deterministic direct-DOM JavaScript generation;
- a tiny handwritten browser host;
- dependent-type dogfood using `Vector` and `Fin`;
- continuous practical dogfooding and browser tests.

The work is successful when the PoC demonstrates that compile-time reactivity and dependent typing provide measurable runtime and correctness value, not merely unusual syntax.

---

## 2. Mandatory reading order

Before modifying code, read in this order:

1. `ARCHITECTURE.md`
2. this `PLAN.md`
3. `README.md`, if already present
4. `STATUS.md`
5. `DECISIONS.md` and all `docs/adr/*.md`
6. `DOGFOOD.md`
7. current test failures
8. the code relevant to the next incomplete milestone

For prior art, inspect:

- Lean’s current official reference for elaborators, syntax extensions, Lake, and compilation;
- Qed’s README, repository layout, JavaScript backend documentation, differential tests, and license;
- do not copy code without recording provenance and preserving license requirements.

---

## 3. Non-negotiable engineering rules

### 3.1 Correctness

- Never add `sorry`, `admit`, or an unreviewed axiom to make progress.
- Do not hide a failed proof behind `native_decide` without an explicit ADR and trust analysis.
- Keep verified semantics total and pure.
- Unsupported browser lowering must fail loudly; never emit guessed JavaScript.
- Never claim the JavaScript backend is formally verified until there is an actual proof connecting it to the source semantics.

### 3.2 Separation of concerns

- Pure compiler phases do not perform file IO.
- The CLI does not contain parsing, graph, scheduling, or codegen semantics.
- The DOM host does not contain reactive scheduling.
- Elaborator metadata is not the sole source of dependency truth.
- Golden formatting is handled by a printer, not embedded throughout lowering.
- Tests may use internal APIs; dogfood examples may use only public APIs.

### 3.3 Source control

- Make one conceptual change per commit.
- Every commit must build and pass the tests relevant to the touched layer.
- Prefer commits that also leave the complete repository green.
- Never commit `WIP`, `misc`, `fix stuff`, `big update`, or equivalent messages.
- Do not squash the implementation history before handoff.
- Do not mix a Lean toolchain bump with feature development.
- Stage files intentionally; inspect `git diff --staged` before committing.
- Preserve unrelated human changes.

### 3.4 Dependencies

- Keep external dependencies minimal.
- Pin the Lean toolchain exactly.
- Commit lockfiles.
- Disable JavaScript lifecycle scripts by default.
- Do not add a package merely to avoid implementing a small, project-specific pure function.
- Record every significant dependency in an ADR or dependency note.

### 3.5 Dogfooding

- A milestone that exposes a user-facing capability is incomplete until a public-API example uses it.
- Every framework bug found through dogfooding becomes a regression test before the fix commit is complete.
- Do not bypass framework limitations with handwritten reactive JavaScript in examples.
- Record usability friction even when it is not fixed immediately.

---

## 4. Working files that Codex must maintain

Create these during Milestone 0 and update them continuously.

### `STATUS.md`

Use this concise structure:

```markdown
# Status

## Current milestone
M2 — Graph semantics

## Last green commit
<hash> <subject>

## Completed
- ...

## In progress
- ...

## Next
- ...

## Known blockers
- None

## Commands
- `lake build`
- `...`
```

Update at least once per milestone and whenever a blocker changes the plan.

### `DECISIONS.md`

Index ADRs:

```markdown
| ADR | Status | Decision | Date |
|---|---|---|---|
| 0001 | Accepted | Lean-hosted staged DSL | 2026-... |
```

### `DOGFOOD.md`

For each example record:

```markdown
## Example name

### Scenario exercised
### What was pleasant
### Friction
### Missing framework capability
### Bugs found
### Performance observations
### Follow-up issue or commit
```

### `NOTICE.md`

Record borrowed/adapted prior-art code, source URL, commit/tag if known, license, modified files, and nature of adaptation.

---

## 5. Review roles

Use separate review passes, and use subagents when the environment supports them. A single implementation pass is not sufficient.

### Lean metaprogramming reviewer

Checks:

- syntax categories and hygiene;
- source spans and diagnostics;
- generated declaration names;
- use of `unsafe` metaprogramming APIs;
- elaborator output being kernel-checkable;
- release-sensitive Lean API usage.

### Type theory and proof reviewer

Checks:

- exact theorem statements;
- dependency-completeness assumptions;
- lawful equality assumptions;
- termination and totality;
- hidden axioms;
- proof vs test boundary;
- whether claims are stronger than the proved model.

### Compiler/backend reviewer

Checks:

- phase boundaries;
- deterministic IR and identifiers;
- unsupported lowering behavior;
- runtime representations;
- JavaScript AST validity;
- source mapping and diagnostics;
- code size and generated control flow.

### Frontend/runtime reviewer

Checks:

- DOM semantics;
- event and property behavior;
- disposal;
- controlled inputs;
- accessibility;
- XSS/URL contexts;
- browser edge cases;
- whether direct updates actually avoid unnecessary DOM writes.

### Test and quality reviewer

Checks:

- negative tests;
- property tests;
- differential coverage;
- browser scenarios;
- flaky timing assumptions;
- dogfood regressions;
- commit granularity and bisectability.

Each milestone ends with explicit notes from all relevant roles in the pull-request description or `STATUS.md`.

---

## 6. Toolchain baseline

Create and pin:

```text
lean-toolchain: leanprover/lean4:v4.33.0
```

Use Lake as the Lean build system.

Use a minimal Node-based browser-test layer. Prefer:

- Node’s built-in test runner for JavaScript unit/differential tests;
- Playwright for real-browser tests;
- `pnpm` with a committed lockfile;
- `.npmrc` containing `ignore-scripts=true` unless a narrowly documented tool requires otherwise.

Do not introduce a bundler in the first milestones. Generated ESM and a static HTML fixture are sufficient.

---

## 7. Milestone overview

| Milestone | Result | Mandatory dogfood |
|---|---|---|
| M0 | reproducible repository and architectural guardrails | none; tooling smoke |
| M1 | typed staged scalar expression core and native evaluator | expression playground |
| M2 | static graph, reference/optimized semantics, theorem skeleton/completion | graph scenarios |
| M3 | typed JavaScript AST, emitter, and runtime representation gate | generated arithmetic module |
| M4 | minimal component DSL, static view, direct DOM Counter | Counter |
| M5 | transactions, equality stop, diamond scheduling, instrumentation | Counter + Diamond lab |
| M6 | dependent-type component API and proof erasure | Dependent Tabs |
| M7 | DOM inputs, parsing, validation, accessibility | Temperature converter + validated form |
| M8 | conditional and keyed dynamic regions | TodoMVC |
| M9 | commands, async resources, ports, cancellation | Notes + Issue browser |
| M10 | structural delta experiment and cost measurement | 10k-row data grid |
| M11 | docs, CLI polish, self-hosting evaluation | LeanRx documentation site |

M0–M6 define the required PoC. M7–M11 are continuation milestones and should begin only after the PoC gate is green.

---

# Milestone 0 — Repository bootstrap and guardrails

## Objective

Create a reproducible Lean project with strict quality gates and no premature framework implementation.

## Tasks

1. Initialize the Lake package and root library.
2. Pin Lean 4.33.0.
3. Add the repository layout needed for M1–M3 without creating empty dozens of files.
4. Add `ARCHITECTURE.md`, `PLAN.md`, `STATUS.md`, `DECISIONS.md`, `DOGFOOD.md`, and `NOTICE.md`.
5. Add ADRs:
   - `0001-lean-host-language.md`
   - `0002-staged-reactive-core.md`
   - `0003-custom-reactive-ir-js-backend.md`
   - `0004-direct-dom-static-shape.md`
   - `0005-trust-boundary.md`
6. Add formatting/lint/test commands.
7. Add CI for `lake build` and a placeholder native test executable.
8. Add JavaScript tooling only when the first JS test is introduced; do not front-load unused dependencies.
9. Add a script or Lean check that scans application/proof modules for banned placeholders.
10. Write `docs/prior-art/qed.md`:
    - factual description;
    - architectural similarities and differences;
    - what may be reused;
    - license handling;
    - no unsupported claims.

## Suggested initial files

```text
LeanRx.lean
LeanRx/Core/SourceInfo.lean
LeanRx/Core/Dependency.lean
Test/Main.lean
lakefile.lean
lean-toolchain
```

## Required tests

- `lake build` succeeds from a clean checkout.
- native test executable returns success.
- banned-placeholder scanner catches a fixture containing `sorry`.
- CI runs on the pinned Lean version.

## Recommended commits

```text
chore(repo): initialize LeanRx Lake package
chore(toolchain): pin Lean 4.33.0
chore(ci): add Lean build and test workflow
docs(architecture): add implementation contracts
docs(adr): record foundational architecture decisions
docs(prior-art): compare Qed and LeanRx
chore(policy): add no-sorry and axiom guardrails
```

## Exit criteria

- clean clone builds with documented commands;
- no framework semantic decision exists only in chat or commit messages;
- status and ADR indexes are current;
- each foundational decision is traceable.

---

# Milestone 1 — Typed staged expression core

## Objective

Implement a small kernel-checked expression language whose type records complete source dependencies, plus a pure native evaluator.

Do not implement JSX, components, DOM, or JavaScript yet.

## Scope

Initial value types:

- `Bool`
- `Int`
- `Nat`
- `String`

Initial operations:

- literals;
- typed field reads;
- integer/natural arithmetic;
- equality and ordering;
- boolean operators;
- string append;
- `if`;
- local `let` if it does not complicate the first-order representation.

## Tasks

1. Define stable typed field IDs and a small schema representation.
2. Define canonical dependency sets and prove/test union laws needed by the compiler.
3. Define a heterogeneous logical `Store`.
4. Define `RxExpr Γ deps α`.
5. Implement native evaluation.
6. Prove `eval_congr_on_deps` by structural recursion.
7. Define runtime representability metadata for initial types.
8. Define lawful equality witnesses for initial types.
9. Add an explicit pretty-printer/serializer for expression debug output.
10. Add an expression playground test module that constructs staged terms directly.

## Design constraints

- The dependency set cannot be a comment or auxiliary mutable table.
- Expression evaluation cannot inspect undeclared fields.
- Do not use dynamic casts in the proof model.
- If an erased executable representation needs casts, isolate it from the typed specification and validate it.

## Required tests

- literal evaluation;
- single-field read;
- two-field binary expression;
- dependency union canonicalization;
- `if` dependencies include condition and both branches conservatively;
- stores equal on dependencies produce equal expression results;
- stores differing only outside dependencies do not affect evaluation;
- Unicode string append;
- integer boundary semantics remain Lean `Int`, not machine `number` semantics.

## Dogfood

Create `examples/00-expression-playground/` or an equivalent native module with:

```text
price
quantity
subtotal = price * quantity
isLarge = subtotal > threshold
label = if isLarge then ... else ...
```

Print expression dependencies and evaluated results for two stores.

Record API friction in `DOGFOOD.md`.

## Recommended commits

```text
feat(core): define typed schemas and fields
feat(core): add canonical dependency sets
feat(core): add heterogeneous logical store
feat(expr): define dependency-indexed scalar expressions
feat(expr): implement pure expression evaluator
proof(expr): prove evaluation depends only on declared fields
feat(runtime): add scalar runtime representations
feat(equality): add lawful scalar equality plans
test(expr): cover staged expression semantics
example(expr): dogfood the scalar expression core
```

## Exit criteria

- no `sorry` in the dependency theorem;
- direct construction of an expression with an omitted dependency is impossible through public constructors;
- the expression example uses only public APIs;
- all tests are deterministic.

---

# Milestone 2 — Graph model, scheduling, and semantics

## Objective

Build static reactive graphs from typed expressions and establish the reference and optimized execution models.

## Scope

Node kinds:

- source;
- derived;
- sink observation.

No DOM yet. Sinks produce abstract values/observations.

## Tasks

1. Define `NodeId`, node kinds, typed node families, and source spans.
2. Build a graph from staged source/derived/sink specifications.
3. Validate dependency IDs and type compatibility.
4. Detect cycles and produce a human-readable cycle path.
5. Generate deterministic topological order and ranks.
6. Define a schedule checker with a theorem that accepted schedules respect all edges.
7. Define full-recomputation reference semantics.
8. Define changed-source transactions.
9. Define optimized pending/actual-change semantics.
10. Prove or complete the smallest central equivalence theorem for finite static DAGs.
11. If the final general theorem is too large for one commit, split it into named lemmas; do not replace it with tests.
12. Add graph JSON and DOT serialization as pure functions.

## Proof strategy

Prefer this decomposition:

1. expression dependency congruence;
2. unaffected nodes preserve values;
3. topological prefix agrees with reference;
4. if lawful equality says unchanged, all consumers observe the same input from that node;
5. affected sink observations agree;
6. batched source transaction equals one reference recomputation from final source state.

Keep the theorem over an abstract graph model. Do not entangle it with DOM or JavaScript.

## Required graph fixtures

- linear chain;
- fan-out;
- fan-in;
- diamond;
- two disconnected components;
- same-value derived stop;
- cycle with two nodes;
- longer cycle with a useful path;
- source write with no consumers.

## Required property tests

Generate small DAGs with operations from a closed scalar set. For event sequences compare:

- final source values;
- final derived values;
- sink observations;
- evaluation counts.

The property runner must accept a fixed seed and print failing cases in a replayable form.

## Dogfood

Create a native “Graph Lab” example that prints:

- graph nodes and edges;
- topological ranks;
- reference result;
- optimized result;
- evaluation counts.

Include the parity case:

```text
count 1 → 3
parity odd → odd
parity consumers not scheduled
```

## Recommended commits

```text
feat(graph): define typed reactive graph model
feat(graph): build graphs from staged expressions
feat(graph): detect cycles with source-linked paths
feat(graph): compute deterministic topological schedules
proof(graph): validate schedule edge ordering
feat(semantics): add full-recomputation reference evaluator
feat(semantics): add changed-source transactions
feat(semantics): add optimized actual-change evaluator
proof(semantics): prove unaffected-node preservation
proof(semantics): prove topological-prefix equivalence
proof(semantics): prove equality-stop soundness
proof(semantics): prove optimized observations match reference
test(graph): add deterministic graph property cases
feat(graph): emit deterministic JSON and DOT
example(graph): add native propagation laboratory
```

## Exit criteria

- abstract optimized/reference equivalence is proved for the declared PoC model;
- cycle diagnostics are useful;
- graph output is byte-deterministic;
- optimized evaluation demonstrates actual work reduction on at least one fixture;
- no browser-specific code exists in semantics or proofs.

---

# Milestone 3 — JavaScript IR, emitter, and differential gate

## Objective

Compile the staged scalar core to deterministic ESM without involving DOM.

## Tasks

1. Define a typed or validity-checked JavaScript AST.
2. Define identifier mangling and collision resolution.
3. Define string and numeric literal emission.
4. Define runtime representations for supported scalar values.
5. Lower `RxExpr` primitives into JavaScript expressions/statements.
6. Emit a module exposing pure evaluator functions.
7. Add readable and compact printer modes.
8. Add a validator that rejects malformed JS AST states before printing.
9. Add Node differential tests comparing native Lean expected results with generated modules.
10. Add unsupported-lowering diagnostics.
11. Add deterministic-build test.
12. Document the ABI.

## Important numeric decision

- `Int` and `Nat` lower to `BigInt` unless an explicitly bounded numeric type is used.
- Add tests for negative `Int`, large values above 2^53, division/modulo semantics used by the supported subset, and conversion to display strings.

## Required tests

- identifier escaping and collision;
- quote, newline, null, and Unicode string escaping;
- arithmetic and comparisons;
- `if`;
- generated module import and execution;
- large integer parity with native Lean;
- deterministic bytes across two builds;
- unsupported primitive fails before output.

## Dogfood

Generate an ESM module for the expression playground and execute it under Node. Compare all outputs to the native evaluator.

## Recommended commits

```text
feat(js): define JavaScript AST and validation
feat(js): add deterministic identifier allocator
feat(js): implement safe JavaScript printer
feat(backend): lower scalar expressions to JavaScript
feat(backend): define scalar runtime ABI
feat(backend): emit standalone ESM evaluators
test(js): cover literals identifiers and invalid AST
test(differential): compare native scalar semantics with JavaScript
test(determinism): byte-compare repeated builds
docs(backend): document runtime representation and trust boundary
example(js): emit and run the expression playground
```

## Exit criteria

- no arbitrary Lean compiler IR dependency exists;
- generated scalar modules run under Node;
- differential tests cover every supported primitive;
- emitter fails loudly on unsupported constructs;
- output is deterministic.

---

# Milestone 4 — Component DSL, static view, and Counter

## Objective

Deliver the first real browser component with public syntax and direct DOM updates.

## Implementation order

Do not start with the final pretty JSX syntax. First make the semantic API work with explicit combinators; then add syntax sugar.

### Step A — Explicit component specification

Implement public constructors for:

- state fields;
- derived nodes;
- event/update definitions;
- static elements;
- text sinks;
- event bindings;
- component manifest.

### Step B — Minimal command elaborator

Add `component` syntax that generates inspectable declarations.

### Step C — Minimal JSX-like view

Support only:

- lowercase static HTML elements;
- static string attributes;
- text literals;
- scalar interpolation;
- `onClick`;
- no lists, fragments, spread attributes, components, or raw HTML.

## Tasks

1. Define `ComponentSpec` and its validation.
2. Define a static DOM IR.
3. Split view into mount template and scalar sinks.
4. Lower component state/derived graph into update functions.
5. Add a tiny `runtime/leanrx_dom.mjs` and `leanrx_host.mjs`.
6. Emit `mount(target) → dispose`.
7. Add component command syntax and source diagnostics.
8. Add minimal view syntax.
9. Add CLI `check`, `build`, and `graph` commands.
10. Build Counter using public APIs only.

## Counter source target

```lean
component Counter where
  state count : Int := 1

  derived doubled : Int := count * 2

  derived parity : String :=
    if count % 2 == 0 then "even" else "odd"

  event increment =>
    set count (count + 1)

  event addTwo =>
    set count (count + 2)

  view =>
    <main class="counter">
      <button onClick={increment}>Increment</button>
      <button onClick={addTwo}>Add two</button>
      <p>{s!"Count: {count}"}</p>
      <p>{s!"Doubled: {doubled}"}</p>
      <p>{s!"Parity: {parity}"}</p>
    </main>
```

The exact syntax may differ slightly only when Lean parser constraints require it. Any deviation must be documented with rationale and examples.

## Required browser tests

- initial DOM content;
- increment updates count/doubled/parity;
- addTwo from 1 to 3 does not write parity text;
- two independent mounts keep separate state;
- dispose removes listeners and DOM;
- dispose twice is safe;
- user text displays as text, not HTML.

## Required compile-fail tests

- mutation in `derived`;
- missing runtime representation;
- missing lawful equality;
- cycle;
- unsupported view expression;
- unknown event attribute;
- raw HTML use.

## Recommended commits

```text
feat(component): define explicit component specifications
feat(view): define static DOM and scalar sink IR
feat(runtime): add minimal browser DOM host
feat(backend): emit component mount and dispose
feat(backend): emit scalar sink updates
feat(elab): add component command elaborator
feat(elab): reify state derived and event declarations
feat(view): add minimal JSX-like static elements
feat(view): add text interpolation and click events
feat(cli): add check build and graph commands
example(counter): dogfood the first browser component
test(browser): verify counter mount update and disposal
test(compile-fail): cover component safety diagnostics
```

## Exit criteria

- Counter runs in a real browser;
- bundle contains no runtime dependency discovery;
- scalar sinks update direct DOM nodes;
- public syntax elaborates to inspectable generated declarations;
- no handwritten reactive code exists in the example.

---

# Milestone 5 — Transactions, diamond graphs, and instrumentation

## Objective

Make the runtime behavior visibly match the architecture under batching, fan-in, nested dispatch, and same-value suppression.

## Tasks

1. Add atomic update transaction evaluation.
2. Record final changed source set by lawful equality.
3. Generate rank-ordered derived phase and separate sink phase.
4. Add nested transaction depth.
5. Add development instrumentation counters.
6. Add optional trace events with stable node names.
7. Add a browser Diamond Lab.
8. Add benchmark harness for small graph propagation.
9. Add derived-read rejection diagnostic with a clear future-capability message.
10. Optionally implement `readDerived` barrier only after the transaction model and proof are updated.

## Required scenarios

### Batched writes

```lean
event addTwoSeparately => do
  set count (count + 1)
  set count (count + 1)
```

Expected:

- one commit;
- each affected derived node evaluates once;
- each pending sink evaluates once;
- no intermediate DOM state.

### Diamond

Expected:

- fan-in node runs once;
- it reads final values of both parents;
- sink never observes mixed old/new parents.

### Same-value stop

Expected:

- `parity` evaluates;
- equality reports unchanged;
- parity sink is not evaluated or written.

## Recommended commits

```text
feat(update): execute events as atomic transactions
feat(runtime): generate topological derived and sink phases
feat(runtime): support nested transaction batching
feat(instrumentation): count evaluations changes and DOM writes
test(browser): verify no intermediate diamond state
test(browser): verify same-value propagation stops
example(diamond): add fan-in propagation laboratory
bench(graph): add scalar propagation benchmarks
docs(runtime): document transaction and trace semantics
```

## Exit criteria

- Counter and Diamond Lab instrumentation matches documented expectations;
- browser tests prove no observable glitch;
- reference and generated execution remain differential-equivalent;
- transaction changes are reflected in the abstract proof model.

---

# Milestone 6 — Dependent types and proof erasure

## Objective

Demonstrate a UI guarantee that mainstream frontend type systems do not naturally provide.

## Primary dogfood: Dependent Tabs

Implement a public component/API where:

- labels and panels have the same statically indexed length;
- at least one tab exists;
- selected is `Fin (n + 1)`;
- selecting out of range cannot be expressed through public APIs;
- browser runtime stores a compact array/index representation;
- proof terms and static length evidence are erased.

## Tasks

1. Add runtime representation rules for `Vector α n` and `Fin n`.
2. Add lowering for safe vector access through `Fin`.
3. Add proof erasure analysis and an IR assertion that erased values are never inspected.
4. Add typed event parameters.
5. Add component props needed for Tabs.
6. Add compile-time examples of valid/invalid construction.
7. Add browser Tabs example.
8. Inspect generated JS to ensure no redundant proof objects are emitted.
9. Document what is guaranteed by Lean and what still depends on backend correctness.

## Required compile-pass cases

- 1 tab;
- 3 tabs;
- selected values constructed safely;
- mapping labels with indices.

## Required compile-fail cases

- label/panel length mismatch;
- empty tabs when API requires `n + 1`;
- invalid unchecked numeric selection for `Fin n`; because pinned Lean's raw
  `OfNat (Fin n)` normalizes modulo, the public Tabs constructor must reject that
  route and require the original `Nat` plus a strict-bound proof (ADR-0011);
- indexing panels with arbitrary `Nat` without proof/check.

## Required browser tests

- click every tab and show matching panel;
- keyboard activation if included;
- public event path never produces invalid selection;
- initial selected panel is correct;
- generated bundle contains no serialized proof terms in the known fixture.

## Recommended commits

```text
feat(rep): add erased Vector runtime representation
feat(rep): add erased Fin runtime representation
feat(backend): lower proof-safe vector indexing
feat(event): support typed event parameters
feat(component): support immutable typed props
example(tabs): dogfood dependent labels panels and selection
test(type): reject mismatched dependent component inputs
test(browser): verify dependent tabs interactions
test(erasure): assert proofs do not reach generated JavaScript
docs(types): explain dependent UI guarantees and trust limits
```

## PoC release gate

M0–M6 are complete only when:

- all `ARCHITECTURE.md` PoC Definition-of-Done items are satisfied;
- there are no `sorry`/`admit` placeholders;
- the propagation theorem is complete for the claimed model;
- Counter, Diamond, and Dependent Tabs run in CI browsers;
- generated code is deterministic;
- at least one benchmark records real work suppression;
- the project states its remaining TCB honestly.

Tag this point as an internal `v0.1.0-poc` only after the gate passes.

---

# Milestone 7 — Controlled inputs and validated forms

## Objective

Test whether the language is practical for everyday form-heavy frontend work.

## Dogfood A — Temperature converter

Requirements:

- Celsius and Fahrenheit text inputs;
- parsing returns an explicit result, not exception;
- no reactive cycle;
- invalid input is preserved for editing;
- the converted value updates only when parsing succeeds;
- typed `input` event payload;
- controlled input cursor behavior is tested.

## Dogfood B — Validated form

Requirements:

- non-empty name;
- bounded numeric field;
- visible accessible error messages;
- submit event available only for valid parsed data, either by typestate or an explicit validated value;
- fake command submission boundary.

## Framework tasks

- DOM properties `value`, `checked`, `disabled`;
- `input`, `change`, `submit`, keyboard/focus events;
- form prevention semantics;
- parser/validator combinators;
- accessible IDs/labels/errors;
- optional refinement/typestate helper API.

## Exit criteria

- examples require no raw JavaScript;
- controlled inputs behave correctly in browser tests;
- invalid form data cannot reach typed submit payload;
- DOGFOOD notes evaluate whether dependent/refinement types improve or harm ergonomics.

---

# Milestone 8 — Conditional and keyed dynamic regions

## Objective

Support practical changing UI shape without introducing a global Virtual DOM.

## Order

1. conditional region;
2. positional list region for simple append/remove;
3. keyed list region;
4. child component ownership if required by TodoMVC.

## Semantic requirements

- scalar sinks inside a stable region remain direct updates;
- only the region reconciles shape;
- keyed identity survives reorder;
- disposal is correct for removed branches/rows;
- region reference semantics and optimized implementation agree.

## Dogfood — TodoMVC

Features:

- create, toggle, edit, delete;
- all/active/completed filter;
- clear completed;
- keyed row identity;
- local editing state;
- browser persistence may wait for M9.

## Required tests

- append/remove/reorder;
- retained row identity;
- edit focus not transferred to wrong row;
- branch disposal;
- event routing after reorder;
- no full-root rebuild for one row toggle;
- differential logical DOM result.

---

# Milestone 9 — Commands, resources, and foreign ports

## Objective

Add controlled interaction with the outside world while keeping updates pure.

## Tasks

- typed `Cmd Msg`;
- command batching;
- timer;
- local storage;
- HTTP request/response;
- cancellation handles;
- resource state;
- stale response suppression;
- explicit foreign ports;
- component disposal cancellation;
- native mocks for differential tests.

## Dogfood A — Notes

- debounced persistence;
- restore from storage;
- cancellation/disposal;
- visible storage error.

## Dogfood B — Issue browser

- HTTP loading/success/failure;
- typed decoding;
- pagination;
- query changes cancel or obsolete prior requests;
- retry;
- no unhandled promise rejection.

## Exit criteria

- effects never run inside derived/view semantics;
- every command has a test double;
- stale async results cannot overwrite newer state;
- disposal cancels owned resources.

---

# Milestone 10 — Structural delta experiment

## Objective

Determine empirically whether structural delta should become a first-class language feature.

## Dogfood — 10k-row data grid

Operations:

- create rows;
- update one row;
- remove rows;
- swap rows;
- filter;
- sort;
- select one row.

## Experiment variants

1. full collection recomputation plus keyed region;
2. explicit `ListDelta` propagation;
3. hybrid cost-based strategy.

## Required measurements

- operation latency;
- allocations;
- derived evaluations;
- DOM operations;
- memory;
- bundle size;
- build time;
- complexity and API burden.

## Decision output

Create an ADR choosing one of:

- structural delta becomes a core feature;
- structural delta remains an opt-in library;
- current keyed recomputation is sufficient;
- more research is required.

Do not declare delta superior without measurements.

---

# Milestone 11 — Documentation, tooling, and self-hosting

## Objective

Evaluate whether another developer can learn and use the framework.

## Tasks

- scaffold command;
- clearer `check/build/graph/doctor` output;
- graph visualization artifact;
- editor-friendly generated declarations;
- language guide;
- architecture guide;
- backend support matrix;
- trust model page;
- dogfood case studies;
- performance report;
- accessibility guide;
- Lean upgrade guide.

## Dogfood — LeanRx documentation site

Build as much of the docs site as feasible with LeanRx itself.

Required pages:

- introduction;
- Counter;
- static graph explanation;
- dependent Tabs;
- effects/resources;
- limitations;
- generated graph viewer.

Record every missing feature encountered. Do not hide limitations by switching the site to another frontend framework without documenting the boundary.

---

## 8. Commit discipline in detail

### 8.1 Commit format

Use Conventional Commit-style subjects:

```text
feat(scope): imperative subject
fix(scope): imperative subject
proof(scope): imperative subject
test(scope): imperative subject
docs(scope): imperative subject
refactor(scope): imperative subject
perf(scope): imperative subject
chore(scope): imperative subject
```

Examples:

```text
feat(expr): add dependency-indexed field reads
proof(expr): prove evaluation congruence on dependencies
fix(schedule): retain fan-in nodes in affected closure
test(browser): catch parity sink over-render
docs(dogfood): record controlled-input cursor issue
```

### 8.2 Commit size

A good commit usually:

- changes one subsystem or introduces one vertical behavior;
- has its tests in the same commit;
- is reviewable without reading future commits;
- can be reverted without corrupting unrelated work.

Do not separate a bug fix from its regression test unless the red test is intentionally committed first and the repository convention permits it.

### 8.3 Before every commit

Run:

1. formatter/linter relevant to touched files;
2. targeted unit/proof tests;
3. `lake build` when Lean interfaces changed;
4. JS tests when backend/runtime changed;
5. browser tests when DOM behavior changed;
6. `git diff --check`;
7. `git diff --staged` review.

### 8.4 Milestone close commit

A milestone close may update only documentation/status/fixtures after feature commits are green:

```text
docs(status): close M4 component and counter milestone
```

Do not use the close commit to hide unreviewed implementation changes.

---

## 9. Testing command contract

Establish stable commands early. Suggested shape:

```text
lake build
lake exe leanrx_test
lake exe leanrx_prop_test -- --seed 1
lake exe leanrx -- check Examples.Counter
lake exe leanrx -- build Examples.Counter --out .tmp/counter
pnpm test
pnpm test:differential
pnpm test:browser
pnpm test:determinism
pnpm test:all
```

Document exact commands in `README.md` and `STATUS.md`.

CI must call the same commands developers use locally; avoid hidden CI-only scripts.

---

## 10. Generated artifact policy

Generated files used only for tests may be committed under `test/golden/`.

Production `dist/` directories MUST NOT be committed unless a release artifact policy later requires it.

Every generated module should have a manifest:

```json
{
  "compilerVersion": "...",
  "leanToolchain": "...",
  "module": "Examples.Counter",
  "graphHash": "...",
  "runtimeAbi": 1,
  "exports": ["mount"],
  "features": ["scalar", "events"]
}
```

The manifest itself must be deterministic.

---

## 11. Performance method

Do not optimize based only on generated-code appearance.

For every optimization:

1. add a benchmark or instrumentation assertion;
2. record baseline;
3. implement optimization;
4. rerun correctness gates;
5. record improvement and regressions;
6. keep the optimization only if benefit justifies complexity.

Particularly scrutinize:

- bitset vs queue scheduling;
- structural equality cost;
- generated code duplication;
- BigInt cost;
- component graph flattening;
- region reconciliation;
- structural delta metadata.

---

## 12. Handling Lean metaprogramming risk

Lean elaborator and compiler APIs can change between releases.

Rules:

- isolate imports of `Lean` internals;
- wrap unstable APIs behind project-owned functions;
- document every internal API dependency in `docs/upgrading-lean.md`;
- prefer public syntax/elaborator APIs;
- use exhaustive matching so changes fail compilation;
- never silently ignore an unknown IR/syntax form;
- keep a small smoke fixture for each custom elaborator feature;
- bump Lean only in a dedicated commit/PR.

The initial custom Reactive IR backend intentionally avoids depending on broad `Lean.IR` internals.

---

## 13. Handling proof difficulty

Do not weaken the claimed theorem silently when a proof becomes difficult.

Use this sequence:

1. state the exact intended theorem;
2. identify the failed lemma/assumption;
3. build a minimal counterexample search using executable semantics;
4. determine whether the theorem is false, underspecified, or merely hard;
5. if false, fix the algorithm or narrow the public claim through an ADR;
6. if true but hard, prove smaller lemmas and keep the executable differential gate;
7. never replace a central proof with comments or tests while continuing to call it proved.

Keep theorem names stable once documented, or provide aliases/deprecation notes.

---

## 14. Security and accessibility gates

Before completing any DOM milestone:

- test hostile text such as `<img src=x onerror=...>` is rendered as text;
- test attributes/properties are context-correct;
- forbid raw HTML by default;
- test listener cleanup;
- test buttons and inputs with keyboard interaction;
- run an automated accessibility scan on dogfood pages;
- document manual checks for labels, focus order, and live errors.

A performance optimization may not bypass safe encoders.

---

## 15. Final review checklist for each milestone

### Architecture

- [ ] implementation follows existing ADRs;
- [ ] no new cross-layer dependency was introduced accidentally;
- [ ] public and internal APIs are distinguished;
- [ ] trust boundary is unchanged or documented.

### Correctness

- [ ] proof obligations are complete for the claimed scope;
- [ ] no placeholders or hidden axioms;
- [ ] negative cases exist;
- [ ] reference and optimized results agree.

### Backend/runtime

- [ ] unsupported cases fail loudly;
- [ ] output is deterministic;
- [ ] differential gate covers new primitives;
- [ ] disposal/error behavior is defined.

### Dogfood

- [ ] public example exercises the feature;
- [ ] browser test exists where relevant;
- [ ] friction is recorded;
- [ ] discovered bugs have regression tests.

### Git history

- [ ] commits are small and descriptive;
- [ ] every commit is buildable or intentionally documented;
- [ ] no unrelated changes are mixed;
- [ ] status documentation reflects reality.

---

## 16. Handoff deliverables

At the end of the assigned implementation window, leave the repository with:

1. green tests or a precise, reproducible failing command;
2. `STATUS.md` naming the current milestone and last green commit;
3. `DOGFOOD.md` with real observations;
4. ADRs for every architecture deviation;
5. no uncommitted generated noise;
6. a bisectable commit history;
7. explicit remaining risks;
8. commands for a human to build, test, inspect a graph, and run the examples;
9. screenshots are optional, but browser assertions are mandatory;
10. no claim of completion beyond the acceptance gates actually passed.

---

## 17. First actions for Codex

Execute these actions in order:

1. Inspect the repository without modifying files.
2. Read `ARCHITECTURE.md` and `PLAN.md` completely.
3. Check whether a prior Rust/`.rxui` implementation exists.
4. Preserve useful research or tests, but do not keep incompatible architecture merely to avoid deletion.
5. Record the migration decision in ADR-0006 if prior implementation exists.
6. Initialize or repair the Lean 4.33.0 Lake project.
7. Add M0 documentation/status files and quality gates.
8. Run and record the clean baseline.
9. Commit M0 in the recommended small sequence.
10. Begin M1 with typed schema/field design, not syntax sugar.

The first user-visible browser milestone is Counter, but the first implementation task is the typed staged core that makes Counter trustworthy.

---

## 18. Completion statement Codex should eventually be able to justify

Do not write this claim in the README until the corresponding gates pass:

> LeanRx compiles a restricted Lean component DSL into a statically known reactive graph and direct DOM JavaScript. For its finite static-DAG core, Lean proves that optimized actual-change propagation has the same abstract observations as full recomputation. Browser code generation remains within a documented trusted boundary and is continuously checked against native semantics and real-browser tests.
