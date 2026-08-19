# LeanRx Architecture

> Working title: **LeanRx**
> Document status: **Normative architecture for the proof of concept**
> Primary audience: Codex and human reviewers implementing the repository
> Last revised: 2026-08-19
> Companion execution plan: [`PLAN.md`](./PLAN.md)

## 0. Normative language

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are normative.

When this document conflicts with ad-hoc implementation convenience, this document wins unless a new Architecture Decision Record (ADR) explicitly changes the decision and records the reason, alternatives, migration impact, and tests.

---

## 1. Executive summary

LeanRx is a Lean 4-hosted frontend language and compiler experiment. It uses Lean for parsing extensions, elaboration, dependent typing, totality checking, theorem proving, and compile-time execution. It does **not** attempt to invent another dependent type theory.

The project’s research question is:

> Can a browser UI program be elaborated into a statically known, dependency-indexed reactive graph; optimized into a fine-grained actual-change propagation plan; and compiled to direct DOM JavaScript while retaining a clear, machine-checkable connection to a simple full-recomputation semantics?

The PoC deliberately separates three concerns:

1. **Lean as the trusted language frontend**
   - ordinary Lean data types, functions, dependent types, proofs, and totality;
   - syntax/command/term elaborators for components, reactive expressions, updates, and views;
   - a small typed staged DSL whose terms carry their dependencies and effects.

2. **A verified or proof-carrying reactive middle end**
   - static state, derived, and sink nodes;
   - complete dependency sets by construction;
   - acyclicity and topological scheduling certificates;
   - a reference evaluator and an optimized evaluator;
   - a central equivalence theorem for actual-change propagation.

3. **A deliberately small browser backend**
   - a typed JavaScript AST and deterministic ESM printer;
   - direct DOM creation and direct sink updates;
   - no general Virtual DOM in the scalar/static-shape path;
   - no runtime subscriber registration, Proxy-based dependency discovery, or `currentObserver` mechanism;
   - a thin hand-written JavaScript host for real DOM APIs and event wiring.

The primary backend for the PoC is **Reactive IR → JavaScript**, not arbitrary Lean IR → JavaScript. This keeps the supported language subset explicit, the generated code small, and the version-dependent surface bounded. A general Lean compiler-IR bridge is a later compatibility project, not a prerequisite for proving the reactive architecture.

---

## 2. Product thesis

### 2.1 The thesis

Reactivity should be a compile-time property whenever it can be proved, and a runtime mechanism only where it cannot.

A conventional signal runtime learns edges dynamically:

```text
observer starts
  → signal read
  → subscriber registration
  → source mutation
  → runtime graph traversal
```

LeanRx should instead compile this:

```lean
state count : Int := 1

derived doubled : Int :=
  count * 2

view =>
  <p>{doubled}</p>
```

into a statically certified relation:

```text
count → doubled → text sink
```

and then emit specialized code:

```javascript
function setCount(next) {
  if (Object.is(count, next)) return;
  count = next;
  pendingCompute |= DOUBLED;
}

function flushDerived() {
  if ((pendingCompute & DOUBLED) !== 0) {
    pendingCompute &= ~DOUBLED;
    const next = count * 2n;
    if (doubled !== next) {
      doubled = next;
      pendingSink |= DOUBLED_TEXT;
    }
  }
}
```

The runtime is therefore an execution plan, not a general reactive discovery engine.

### 2.2 What “better types” means here

LeanRx does not promise that all bugs disappear. It aims to make the following classes of invalid programs unrepresentable or build failures:

- a derived expression mutating component state;
- an event writing a field outside its declared write capability;
- a view performing IO;
- a reactive dependency cycle;
- an intended out-of-range `Fin n` selection through a public constructor
  (raw Lean `OfNat (Fin n)` syntax is not accepted at that boundary because it
  normalizes modulo on the pinned toolchain; see ADR-0011);
- a `Vector α n` length mismatch;
- a non-exhaustive match;
- a partial or non-terminating function in verified application code;
- an unknown DOM property or event in the safe view DSL;
- a component contract whose proof does not hold;
- an optimizer schedule that is not topological;
- a dependency manifest that omits a state read.

The JavaScript emitter and browser host remain part of the trusted computing base in the PoC. Their correctness is defended through a small surface, fail-loud lowering, golden tests, native-vs-JS differential tests, and browser tests. A mechanically verified backend is a later objective.

---

## 3. Goals

The PoC MUST demonstrate all of the following.

1. A Lean 4 file can declare a component with typed state, pure derived values, atomic events, and a typed view.
2. Reactive dependencies are known at build time.
3. The browser bundle contains no runtime dependency discovery.
4. A source change only schedules direct consumers.
5. A derived node only propagates when its value actually changes according to a lawful equality strategy.
6. Diamond graphs are glitch-free.
7. Multiple writes in one event are batched into one commit.
8. The optimized evaluator has the same observable result as a full-recomputation reference evaluator for the supported model.
9. A dependent-type example uses `Vector`/`Fin` or an equivalent indexed API to rule out an actual UI error.
10. Generated JavaScript mounts, updates, and disposes a real browser DOM.
11. Compiler phases are independently testable and do not hide semantics inside the CLI or file-system layer.
12. Practical examples are developed continuously as dogfood, not added after the compiler is considered finished.

---

## 4. Non-goals for the initial PoC

The initial PoC MUST NOT attempt all of the following at once:

- full React/Vue/Svelte ecosystem compatibility;
- parsing JavaScript or TypeScript as the source language;
- arbitrary Lean-to-JavaScript compilation;
- a production bundler;
- CSS preprocessing;
- SSR and hydration;
- HMR with state preservation;
- concurrent rendering;
- browser extension targets;
- full Web Components interoperability;
- arbitrary dynamic dependency graphs;
- arbitrary reflection or `eval` in application code;
- a general theorem prover UI;
- a complete structural-delta implementation before scalar reactivity is correct;
- formal verification of the JavaScript engine or browser DOM.

These may become later milestones only after the central static-graph thesis is validated.

---

## 5. Architectural decisions

### ADR-001 — Lean 4 is the host language

**Decision:** Application and framework source are Lean 4 modules. Lean syntax extensions provide the UI surface language.

**Reason:** Lean already supplies dependent types, inductive families, `Fin`, `Vector`, totality, elaboration, a kernel, macros, custom command/term elaborators, an LSP, and Lake.

**Consequence:** The project inherits Lean’s syntax, compilation model, release cadence, and metaprogramming constraints.

### ADR-002 — Greenfield core; Qed is prior art, not a required dependency

**Decision:** Build a new, narrowly scoped core. Study Qed’s MIT-licensed implementation, tests, JavaScript backend, trust-boundary documentation, and dogfooding discipline. Do not begin by forking its Virtual DOM/Elm architecture wholesale.

**Reason:** Qed demonstrates that Lean-hosted frontend code and Lean-IR-to-JavaScript transpilation are practical. LeanRx investigates a different center of gravity: dependency-indexed expressions, static fine-grained graphs, actual-change propagation, and direct DOM sinks.

**Consequence:** Any copied or adapted Qed code MUST preserve license notices and provenance in `NOTICE.md` and source comments. A prior-art comparison MUST live in `docs/prior-art/qed.md`.

### ADR-003 — A typed staged DSL is the semantic boundary

**Decision:** Reactive expressions, updates, and views elaborate to explicit typed Lean terms such as `RxExpr`, `Update`, and `View`, rather than being treated as unrestricted ordinary Lean functions over the whole component state.

**Reason:** Dependency and effect information must be complete by construction. An unrestricted function `State → α` can inspect arbitrary fields and defeats precise dependency inference.

**Consequence:** Ordinary Lean helper functions are allowed when they receive already-read values. Functions that themselves represent reactive reads must return or manipulate staged terms.

### ADR-004 — Primary backend is custom Reactive IR → JavaScript

**Decision:** The PoC lowers the typed reactive program into a custom first-order IR and then a typed JavaScript AST.

**Reason:** Lean compiler IR is powerful but internal and release-sensitive. A custom backend supports a smaller, explicit language subset and reduces the amount of Lean runtime representation that must be reproduced in JavaScript.

**Consequence:** Not every Lean function is browser-lowerable. Unsupported constructs fail at build time with source-linked diagnostics. A later `LeanIRBridge` may broaden support.

### ADR-005 — Direct DOM for static shape

**Decision:** Static element structure is created once. Reactive text, attributes, properties, and event handlers become explicit sink nodes. Scalar updates write directly to their corresponding DOM locations.

**Reason:** A Virtual DOM would obscure the static-graph thesis and add work for paths whose target DOM node is already known.

**Consequence:** Dynamic branches and lists are represented as explicit dynamic regions and are deferred until after scalar correctness.

### ADR-006 — Atomic event transactions

**Decision:** An event may perform multiple logical state writes, but no derived recomputation or DOM mutation becomes externally visible until commit. At commit, the graph is evaluated in topological order and sinks run afterward.

**Reason:** This prevents glitches and duplicate work.

### ADR-007 — Actual-change propagation

**Decision:** A changed source marks only direct consumers as pending. A pending derived node is evaluated once when its rank is processed. It marks its consumers only if lawful equality reports an actual value change.

**Reason:** This captures the useful behavior commonly described as push–pull–push while compiling away general runtime graph machinery.

### ADR-008 — Proofs and executable tests are complementary

**Decision:** The abstract propagation algorithm must have a Lean correctness argument. The JavaScript backend must additionally pass differential and browser tests.

**Reason:** A proof about a source semantics does not automatically prove a custom emitter or DOM host correct.

### ADR-009 — Stable toolchain pin

**Decision:** Pin an exact stable Lean toolchain in `lean-toolchain`. At document time, the recommended initial pin is `leanprover/lean4:v4.33.0`, not a release candidate.

**Consequence:** Toolchain upgrades are explicit pull requests with an upgrade checklist and differential gate.

---

## 6. Prior art boundary

### 6.1 Qed

Qed is a Lean 4 frontend framework that transpiles Lean compiler IR to JavaScript and uses a typed Virtual DOM, diffing, Elm-style pure reducers, invariants, routing, schemas, effects, SSR, examples, and native-vs-JavaScript gate tests.

LeanRx SHOULD learn from Qed in these areas:

- a very thin handwritten DOM/host boundary;
- fail-loud unsupported JavaScript lowering;
- differential probes between native Lean and transpiled JavaScript;
- explicit no-`sorry` and axiom policies;
- examples as a guided tour and regression suite;
- version-dependent compiler surface documentation;
- license clarity.

LeanRx intentionally differs in these areas:

| Concern | Qed prior art | LeanRx PoC |
|---|---|---|
| update model | Elm-style model/message/reducer | dependency-indexed state/update program |
| view engine | typed VDOM plus proven diff/value patches | static DOM template plus direct sinks |
| dependency granularity | view bindings/subtrees | explicit state/derived/sink graph |
| propagation | view rebuild/patch strategy | actual-change topological propagation |
| primary JS lowering | broad Lean compiler IR transpilation | custom staged Reactive IR emitter |
| proof focus | reducer/view/diff contracts | dependency completeness and optimized-vs-reference graph semantics |

### 6.2 Svelte, Solid, signal libraries, and incremental computation

The implementation MAY study compiler-generated DOM updates, runtime fine-grained graphs, versioning, pending/dirty states, incremental λ-calculus, self-adjusting computation, and differential dataflow. These are conceptual inputs, not dependencies.

The PoC must remain falsifiable: benchmark the generated code and record where static compilation wins, loses, or merely moves complexity to build time.

---

## 7. System context

```text
┌────────────────────────────────────────────────────────────────────┐
│                         Application.lean                           │
│ ordinary Lean + component/event/derived/view syntax               │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ parsing + elaboration
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│                  Kernel-checked staged terms                       │
│ Schema · Field · RxExpr · Update · View · ComponentSpec           │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ extraction/lowering
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│                        Reactive Core IR                            │
│ typed nodes · deps · effects · equality · source spans             │
└───────────────┬──────────────────────────────┬─────────────────────┘
                │                              │
                │ semantics/proofs             │ planner
                ▼                              ▼
┌──────────────────────────┐       ┌────────────────────────────────┐
│ Reference evaluator      │       │ Graph + topological schedule   │
│ full recomputation       │       │ dirty closure + sink plan      │
└──────────────┬───────────┘       └───────────────┬────────────────┘
               │ equivalence theorem/             │ lowering
               │ differential oracle              ▼
               │                    ┌────────────────────────────────┐
               └───────────────────►│ JavaScript MIR / typed JsAst  │
                                    └───────────────┬────────────────┘
                                                    │ deterministic emit
                                                    ▼
                                    ┌────────────────────────────────┐
                                    │ ESM component modules          │
                                    │ direct DOM update functions    │
                                    └───────────────┬────────────────┘
                                                    │ imports
                                                    ▼
                                    ┌────────────────────────────────┐
                                    │ tiny handwritten browser host  │
                                    │ DOM calls · event bridge        │
                                    └────────────────────────────────┘
```

---

## 8. Repository layout

The repository SHOULD converge on this layout. Files may begin smaller, but responsibilities MUST remain separated.

```text
.
├── ARCHITECTURE.md
├── PLAN.md
├── README.md
├── STATUS.md
├── DOGFOOD.md
├── DECISIONS.md
├── NOTICE.md
├── lean-toolchain
├── lakefile.lean
├── lake-manifest.json
├── package.json
├── pnpm-lock.yaml
├── .npmrc
├── .editorconfig
├── .github/
│   └── workflows/
│       ├── lean.yml
│       ├── browser.yml
│       └── determinism.yml
├── LeanRx.lean
├── LeanRx/
│   ├── Core/
│   │   ├── Schema.lean
│   │   ├── Dependency.lean
│   │   ├── Expr.lean
│   │   ├── Update.lean
│   │   ├── View.lean
│   │   ├── Component.lean
│   │   ├── Equality.lean
│   │   └── SourceInfo.lean
│   ├── Syntax/
│   │   ├── Component.lean
│   │   ├── Expr.lean
│   │   ├── Update.lean
│   │   └── Jsx.lean
│   ├── Elab/
│   │   ├── Component.lean
│   │   ├── ReifyExpr.lean
│   │   ├── ReifyUpdate.lean
│   │   ├── ReifyView.lean
│   │   ├── Diagnostics.lean
│   │   └── Registry.lean
│   ├── Graph/
│   │   ├── Model.lean
│   │   ├── Build.lean
│   │   ├── Cycle.lean
│   │   ├── Topological.lean
│   │   └── Certificate.lean
│   ├── Semantics/
│   │   ├── Store.lean
│   │   ├── Reference.lean
│   │   ├── Optimized.lean
│   │   └── Observation.lean
│   ├── Proofs/
│   │   ├── DependencySound.lean
│   │   ├── ScheduleSound.lean
│   │   ├── PropagationSound.lean
│   │   └── TransactionSound.lean
│   ├── IR/
│   │   ├── Reactive.lean
│   │   ├── Dom.lean
│   │   ├── Js.lean
│   │   └── Validate.lean
│   ├── Lower/
│   │   ├── Reactive.lean
│   │   ├── Dom.lean
│   │   ├── Builtins.lean
│   │   └── Erasure.lean
│   ├── Backend/
│   │   ├── JsAst.lean
│   │   ├── Emit.lean
│   │   ├── Printer.lean
│   │   ├── Names.lean
│   │   └── SourceMap.lean
│   ├── Runtime/
│   │   ├── Reference.lean
│   │   ├── Instrumentation.lean
│   │   └── Foreign.lean
│   └── Cli/
│       ├── Main.lean
│       ├── Build.lean
│       ├── Check.lean
│       ├── Graph.lean
│       └── Doctor.lean
├── runtime/
│   ├── leanrx_dom.mjs
│   ├── leanrx_host.mjs
│   └── leanrx_devtools.mjs
├── examples/
│   ├── 01-counter/
│   ├── 02-temperature/
│   ├── 03-tabs-dependent/
│   ├── 04-form/
│   ├── 05-todomvc/
│   ├── 06-notes/
│   ├── 07-issue-browser/
│   └── 08-data-grid/
├── test/
│   ├── lean/
│   ├── compile-pass/
│   ├── compile-fail/
│   ├── golden/
│   ├── differential/
│   ├── browser/
│   └── fixtures/
├── bench/
│   ├── propagation/
│   ├── generated-size/
│   └── data-grid/
└── docs/
    ├── adr/
    ├── language/
    ├── internals/
    ├── prior-art/
    └── upgrading-lean.md
```

### 8.1 Layering rule

Dependencies MUST point downward:

```text
Syntax/Elab
    ↓
Core
    ↓
Graph/Semantics/Proofs
    ↓
IR/Lower
    ↓
Backend
    ↓
Cli and external IO shell
```

`Core`, `Graph`, `Semantics`, `Proofs`, `IR`, and `Backend` MUST NOT read files, inspect process environment variables, start servers, or invoke Node. The CLI owns file-system and process IO.

---

## 9. User-facing language

### 9.1 Initial surface

The target syntax is intentionally familiar while remaining a Lean extension:

```lean
import LeanRx

component Counter where
  state count : Int := 1

  derived doubled : Int :=
    count * 2

  derived parity : String :=
    if count % 2 == 0 then "even" else "odd"

  event increment =>
    set count (count + 1)

  event addTwo =>
    set count (count + 2)

  view =>
    <main class="counter">
      <h1>Counter</h1>
      <button onClick={increment}>Increment</button>
      <button onClick={addTwo}>Add two</button>
      <p>{s!"Count: {count}"}</p>
      <p>{s!"Doubled: {doubled}"}</p>
      <p>{s!"Parity: {parity}"}</p>
    </main>
```

This is a design target, not permission to put all parsing and semantics into one command elaborator. The elaborator MUST lower into explicit core terms and generated declarations.

### 9.2 Generated declarations

A component elaboration SHOULD produce inspectable declarations similar to:

```lean
namespace Counter

structure State where
  count : Int

def init : State :=
  { count := 1 }

inductive Event where
  | increment
  | addTwo

def doubledExpr : RxExpr schema {countField} Int := ...

def parityExpr : RxExpr schema {countField} String := ...

def incrementUpdate : Update schema {countField} {countField} Unit := ...

def addTwoUpdate : Update schema {countField} {countField} Unit := ...

def viewSpec : View schema Event := ...

def spec : ComponentSpec := ...

end Counter
```

Generated declaration names MUST be deterministic and discoverable with `#check`, editor navigation, and `#print` where practical.

### 9.3 Staged boundary

The following is allowed because the helper receives values rather than state capabilities:

```lean
def totalPrice (price quantity : Int) : Int :=
  price * quantity

component Cart where
  state price : Int := 0
  state quantity : Int := 1

  derived total : Int :=
    totalPrice price quantity
```

The expression reifier may inline or lower `totalPrice` only if it is in the supported pure subset or registered with a lowering rule.

The following unrestricted state escape MUST be rejected:

```lean
def inspectWholeState (s : Cart.State) : Int :=
  -- arbitrary future field access
  ...

derived total := inspectWholeState state
```

Application code MUST NOT obtain a first-class mutable state object or a reflective field iterator.

---

## 10. Core type model

The exact Lean definitions may evolve, but they MUST preserve the following semantic separation.

### 10.1 Schema and fields

A schema is a compile-time description of heterogeneously typed state fields.

A representative design:

```lean
structure FieldSpec where
  name : Name
  ty : Type
  runtime : RuntimeRep ty

structure Schema where
  fields : Array FieldSpec

structure Field (Γ : Schema) (α : Type) where
  index : Fin Γ.fields.size
  type_eq : Γ.fields[index].ty = α
  name_eq : Γ.fields[index].name = name
```

The implementation MAY choose a universe-polymorphic or code-indexed representation to avoid storing `Type` directly in data. The required property is:

> A `Field Γ α` is an unforgeable, typed capability to read or write one field of type `α` in schema `Γ`.

### 10.2 Dependency sets

Dependencies SHOULD be canonical finite sets over field or node IDs.

```lean
abbrev FieldId (Γ : Schema) := Fin Γ.fields.size
abbrev DepSet (Γ : Schema) := Finset (FieldId Γ)
```

Canonical ordering is required for deterministic graph and code generation.

### 10.3 Reactive expressions

A conceptual GADT:

```lean
inductive RxExpr (Γ : Schema) : DepSet Γ → Type → Type where
  | literal
      (value : α)
      [RuntimeRep α]
      : RxExpr Γ ∅ α

  | read
      (field : Field Γ α)
      : RxExpr Γ {field.index} α

  | unary
      (op : UnaryPrim α β)
      (x : RxExpr Γ dx α)
      : RxExpr Γ dx β

  | binary
      (op : BinaryPrim α β γ)
      (x : RxExpr Γ dx α)
      (y : RxExpr Γ dy β)
      : RxExpr Γ (dx ∪ dy) γ

  | ifThenElse
      (condition : RxExpr Γ dc Bool)
      (yes : RxExpr Γ dy α)
      (no : RxExpr Γ dn α)
      : RxExpr Γ (dc ∪ dy ∪ dn) α

  | letExpr
      (value : RxExpr Γ dv α)
      (body : Local α → RxExpr Γ db β)
      : RxExpr Γ (dv ∪ db) β
```

The implementation need not use HOAS if it makes extraction difficult. A first-order locally nameless or de Bruijn representation is acceptable. The kernel-checked term MUST determine its complete dependency set.

### 10.4 Dependency soundness

Every expression MUST carry or admit a theorem equivalent to:

```lean
theorem eval_congr_on_deps
    (expr : RxExpr Γ deps α)
    (s₁ s₂ : Store Γ)
    (h : ∀ field, field ∈ deps → s₁.get field = s₂.get field) :
  eval expr s₁ = eval expr s₂
```

Ideally this theorem is proved once by structural induction over `RxExpr`.

This theorem is the semantic meaning of “the compiler knows all dependencies.”

### 10.5 Updates

Events use a staged update program, not raw mutation:

```lean
inductive Update
    (Γ : Schema)
    : DepSet Γ → DepSet Γ → Type → Type where
  | pure : α → Update Γ ∅ ∅ α
  | read : Field Γ α → Update Γ {field.index} ∅ α
  | set  : Field Γ α → RxExpr Γ deps α → Update Γ deps {field.index} Unit
  | bind : Update Γ r₁ w₁ α
         → (α → Update Γ r₂ w₂ β)
         → Update Γ (r₁ ∪ r₂) (w₁ ∪ w₂) β
```

This is conceptual. The implementation MAY separate a typed transaction AST from its evaluator to avoid higher-order extraction.

Required properties:

- only `Update` can write state;
- `RxExpr` and `View` cannot write state;
- event read/write sets are statically available;
- an event executes against a logical transaction store;
- DOM effects are impossible inside the update language;
- foreign effects are returned as typed commands, not executed in the reducer/update evaluator.

### 10.6 Runtime representation

Every value reaching browser runtime MUST have an explicit representability witness.

```lean
class RuntimeRep (α : Type u) where
  jsType : JsType
  eraseProofs : Bool
  equality : EqualityPlan α
```

Initial required representations:

| Lean source type | JavaScript representation | Notes |
|---|---|---|
| `Bool` | `boolean` | exact |
| `String` | `string` | Unicode behavior must be tested |
| `Int` | `bigint` | preserve unbounded integer semantics |
| `Nat` | non-negative `bigint` | constructors/operations preserve non-negativity |
| `Float` | `number` | IEEE semantics |
| `UInt32` | `number` | unsigned masking where required |
| `Option α` | tagged object or `null` only when proven unambiguous | choose one stable ABI |
| product/structure | fixed-shape object or array | deterministic field order |
| `Vector α n` | array of `α` | `n` and proofs erased |
| `Fin n` | integer index | proof erased; constructors are compiled safely |
| propositions/proofs | erased | never inspected at runtime |

Lean `Int` MUST NOT silently map to JavaScript `number` in the semantics-preserving backend.

For ergonomic UI arithmetic, the standard library MAY expose explicitly bounded numeric types such as `I32`, `U32`, or `SafeInt` with `number` representations.

### 10.7 Lawful equality

Actual-change propagation requires a lawful equality plan.

```lean
class RuntimeEq (α : Type u) [RuntimeRep α] where
  eq : α → α → Bool
  lawful : ∀ a b, eq a b = true ↔ a = b
  jsLowering : JsEqPlan
```

Initial derived values MUST require a supported `RuntimeEq`.

Reference identity MAY be offered later as an explicit weaker strategy, but it MUST have different semantics and naming. It must not masquerade as propositional equality.

---

## 11. Elaboration pipeline

### 11.1 Phases

```text
Lean parser
  → component command elaborator
  → declaration collection
  → schema generation
  → expression/update/view reification
  → ordinary Lean type checking and unification
  → staged term construction
  → generated declaration registration
  → graph extraction
  → graph validation/certification
  → lowering and code generation
```

### 11.2 The elaborator is not the semantic source of truth

Elaborator code may be complicated and may use Lean metaprogramming APIs. It MUST produce explicit core terms that ordinary Lean checking can validate.

Dependency lists MUST NOT exist only as mutable elaborator metadata. They must be derivable from the staged term or accompanied by a checkable certificate.

### 11.3 Reification strategy

The expression reifier MUST initially support a closed subset:

- literals;
- state/derived references;
- `if`;
- `match` over supported finite/inductive forms;
- local `let`;
- arithmetic and comparison primitives;
- boolean operators;
- string concatenation/interpolation;
- tuples and supported structures;
- calls to registered pure lowerable functions.

Unsupported ordinary Lean terms MUST fail loudly:

```text
error: expression is well-typed Lean but is not browser-lowerable by LeanRx

  unsupported call: MyModule.arbitraryRecursiveFunction

  help:
  - rewrite it using LeanRx-supported primitives;
  - mark a transparent total helper with `@[leanrx_inline]`;
  - provide a tested lowering in `Lower.Registry`;
  - or keep the computation on the server/foreign boundary.
```

### 11.4 Lowering registry

A compile-time registry maps Lean constants to typed IR primitives or inlining policies.

```lean
structure LoweringRule where
  source : Name
  arity : Nat
  validateTypes : Array Expr → MetaM LoweredSignature
  lower : Array ReactiveIR.ValueId → LowerM ReactiveIR.ValueId
```

Rules MUST be deterministic and source-located. Registration conflicts MUST be build errors.

### 11.5 Diagnostics

All user-facing elaboration failures MUST:

- point to the original source syntax;
- identify the failed phase;
- explain the invariant in plain language;
- include the inferred and expected Lean types where relevant;
- provide one actionable correction;
- avoid exposing raw metavariable internals unless a verbose flag is enabled.

Compile-fail tests MUST snapshot stable error codes and key messages, not fragile whitespace from the entire Lean diagnostic.

---

## 12. Reactive graph model

### 12.1 Node kinds

```lean
inductive NodeKind where
  | source
  | derived
  | sink
  | dynamicRegion   -- later milestone
  | commandBoundary -- later milestone
```

Each node requires:

```lean
structure Node where
  id : NodeId
  name : Name
  kind : NodeKind
  valueType : RuntimeTypeId
  deps : Array NodeId
  rank : Nat
  equality : Option EqualityPlan
  span : SourceSpan
  evaluator : EvaluatorId
```

Sources have no evaluator. Sinks have no reactive consumers in the scalar model.

### 12.2 Edge completeness

An edge `a → b` means `b` may observe `a` while evaluating. Missing an edge is unsound. Extra edges are sound but less efficient.

The architecture aims to make missing edges impossible by constructing graph dependencies from `RxExpr` indices.

### 12.3 Cycles

Derived cycles are compile errors.

```lean
state a : Int := 0

derived b := c + 1
derived c := b + 1
```

Expected diagnostic:

```text
error[LRX-GRAPH-001]: reactive dependency cycle

  b → c → b

  b declared at App.lean:4:3
  c declared at App.lean:5:3
```

Events may write sources that derived nodes read; this is not a graph cycle because event execution and commit are phase-separated.

### 12.4 Topological schedule

The graph builder MUST produce:

```lean
structure Schedule (g : Graph) where
  order : Array NodeId
  complete : ...
  noDuplicates : ...
  respectsEdges : ∀ edge ∈ g.edges, position edge.from < position edge.to
```

For the first implementation, a decidable checker may validate a generated order. The eventual preferred design is a proof-producing topological sorter.

### 12.5 Stable IDs

Node IDs in emitted artifacts MUST be deterministic for identical source. They MUST NOT depend on hash-map iteration order, memory addresses, or process-specific names.

Recommended key:

```text
module name + component name + declaration order + node role
```

A content hash MAY be added for cache invalidation, not as the only human-facing identifier.

---

## 13. Transaction and propagation semantics

### 13.1 Event transaction

An event executes in four conceptual phases:

```text
1. begin transaction
2. evaluate update program against transaction-local current state
3. record which source fields changed by lawful equality
4. commit: derived phase, then sink phase, then command dispatch
```

No DOM sink runs during phase 2.

### 13.2 Multiple writes

```lean
event addTwoSeparately => do
  set count (count + 1)
  set count (count + 1)
```

The final logical source change is `count: old → old + 2`. Derived nodes are evaluated at most once at commit.

### 13.3 Pending and changed

The runtime does not need a fully general `Pending` object per node. The compiler may emit bitsets, booleans, or compact queues.

Conceptually:

```text
source write
  → mark direct consumers pending
  → process pending derived nodes by topological rank
  → compare old and new value
  → if equal: stop at that node
  → if changed: store new value and mark direct consumers pending
  → after derived fixed point: evaluate pending sinks
```

Because the graph is acyclic and each source transaction is finite, one topological pass over the affected closure is sufficient. There is no iterative fixed-point search.

### 13.4 Diamond graph

```text
      count
      /   \
     a     b
      \   /
       total
         |
        sink
```

If `count` changes, `total` MUST evaluate only after both `a` and `b` have either updated or been proven unchanged. Topological rank enforces this.

### 13.5 Derived reads inside events

Initial milestone policy:

- ordinary source reads inside events are supported;
- direct reads of a `derived` value inside an event are rejected until an on-demand barrier is implemented.

Later policy:

```text
read derived d during transaction
  → flush pending derived nodes up to rank(d)
  → do not run DOM sinks
  → return current d
```

This capability MUST be explicit in `Update` and covered by transaction semantics proofs. It must never return a stale cache.

### 13.6 Reentrancy

Event handlers that synchronously dispatch another event are nested transactions. Only the outermost transaction commits.

Asynchronous callbacks always begin a new transaction.

### 13.7 Error behavior

Verified application code should avoid exceptions. Browser host failures, missing mount targets, or unsupported foreign behavior produce explicit `Result`/error callbacks or a fatal developer diagnostic. The framework MUST NOT silently continue with a partially committed graph.

---

## 14. Reference and optimized semantics

### 14.1 Dependent store

A graph has a family of node value types:

```lean
abbrev Store (Ty : NodeId → Type) :=
  (id : NodeId) → Ty id
```

The executable implementation may use erased arrays and runtime type IDs, but proofs SHOULD use a typed model.

### 14.2 Reference evaluator

For every committed source state:

```text
- evaluate all derived nodes in topological order;
- evaluate all sinks from the resulting store;
- produce an abstract observable DOM/value model.
```

The reference evaluator does not optimize based on dirty sets. It is intentionally simple and acts as the semantic oracle.

### 14.3 Optimized evaluator

The optimized evaluator:

```text
- starts from a changed-source set;
- traverses only its affected closure;
- evaluates each affected derived node once in topological order;
- stops propagation at equal derived values;
- evaluates only pending sinks.
```

### 14.4 Central theorem

The target theorem is conceptually:

```lean
theorem optimized_equivalent_to_reference
    (p : Program)
    (wf : p.WellFormed)
    (schedule : Schedule p.graph)
    (old : Store p.Ty)
    (tx : SourceTransaction p)
    (depSound : p.DependencyComplete)
    (eqSound : p.EqualitiesLawful) :
  observe (runOptimized p schedule old tx)
    =
  observe (runReference p old tx)
```

The proof MAY be decomposed into:

1. unaffected-node preservation;
2. topological-prefix equivalence;
3. equality-stop soundness;
4. sink observation equivalence;
5. transaction batching equivalence.

### 14.5 Proof scope for PoC

The minimum acceptable proof scope is an abstract finite DAG model with:

- pure deterministic evaluators;
- complete declared dependencies;
- lawful equality;
- a valid topological schedule;
- source, derived, and sink nodes;
- no dynamic graph shape.

The connection from component elaboration to this model SHOULD be kernel-checked by typed construction or certificates.

The connection from JavaScript execution to the model is tested, not fully proved, in the PoC.

---

## 15. View and DOM model

### 15.1 Static template

A view is split at compile time into:

```text
static DOM template
+ dynamic scalar sinks
+ event bindings
+ dynamic regions (later)
```

Example:

```lean
view =>
  <p class="count">{s!"Count: {count}"}</p>
```

becomes:

```text
mount:
  createElement("p")
  setStaticAttribute("class", "count")
  createTextNode(initialText)

sink:
  countText.data = nextText
```

### 15.2 Sink kinds

Initial sink kinds:

```lean
inductive SinkKind where
  | textData
  | attribute
  | booleanAttribute
  | property
  | className
  | styleProperty
```

Each sink has a typed encoder and equality strategy.

### 15.3 Safe DOM DSL

The safe JSX-like DSL MUST:

- use text nodes for interpolated strings;
- reject unknown event names;
- distinguish attributes from DOM properties;
- provide typed event payloads;
- escape or disallow unsafe URL/property contexts;
- exclude raw `innerHTML` from the default API;
- make explicit foreign/raw HTML an audited capability.

### 15.4 Event wiring

Generated component modules export `mount(target, props?) → dispose`.

The handwritten host provides primitive operations such as:

```javascript
export function createElement(tag) { ... }
export function createText(data) { ... }
export function listen(node, type, handler) { ... }
export function setText(node, value) { ... }
export function setProperty(node, name, value) { ... }
```

The host must be tiny, versioned, and browser-tested. It MUST NOT implement reactive scheduling.

### 15.5 Disposal

`dispose` MUST:

- be idempotent;
- remove event listeners;
- cancel registered commands/resources;
- dispose child components and dynamic regions;
- detach owned DOM nodes;
- make post-disposal dispatch a no-op or explicit developer error.

### 15.6 Dynamic regions

Conditionals and lists are postponed until scalar DOM is stable.

Later region types:

```text
ConditionalRegion
KeyedListRegion
PositionalListRegion
ChildComponentRegion
PortalRegion
```

A dynamic region may use a local reconciler. This does not justify introducing a global Virtual DOM.

---

## 16. JavaScript backend

### 16.1 Typed JavaScript AST

Code generation MUST NOT be a collection of unrelated string concatenations.

Minimum AST categories:

```lean
inductive JsExpr
inductive JsStmt
inductive JsDecl
structure JsModule
structure JsImport
structure JsExport
```

The AST should encode identifier vs string literal distinctions and make invalid syntax difficult to construct.

### 16.2 Output contract

Generated output:

- is deterministic ESM;
- has no `eval` or `new Function`;
- imports only declared runtime-host functions;
- does not require a general Lean runtime for the initial staged subset;
- includes optional readable development mode and compact production mode;
- can emit a source map or at least source comments after the core compiler works;
- fails the build on unsupported IR.

### 16.3 ABI

The backend MUST document an ABI for:

- primitive values;
- structures and tagged unions;
- closures, if supported;
- component state storage;
- event arguments;
- commands and async results;
- child component handles;
- disposed state.

ABI changes require an ADR and a major internal version bump.

### 16.4 Builtin lowering

Start with explicit primitives, for example:

```text
Int.add / sub / mul / mod / compare
Nat operations
Bool operations
String.append / interpolation
Option constructors and match
selected Array/Vector reads
Fin value erasure
```

Every primitive requires:

- native Lean semantics tests;
- generated JavaScript tests;
- edge-case vectors;
- an entry in `docs/internals/runtime-representation.md`.

### 16.5 Why not arbitrary Lean IR first

A general Lean IR backend must reproduce broad Lean runtime conventions, closures, constructors, arrays, reference-counting optimizations, tail calls, externs, and internal IR changes. Qed proves this is possible, but it is a separate large project.

LeanRx’s first backend compiles only the staged core whose semantics it owns. This creates a meaningful PoC sooner and makes unsupported computation visible.

### 16.6 Future Lean IR bridge

A later isolated package MAY add:

```text
Lean compiler IR
  → compatibility lowering
  → LeanRx JsAst/runtime ABI
```

If added, all Lean-version-dependent code MUST live under `LeanRx/Backend/LeanIR/`, and `docs/upgrading-lean.md` MUST enumerate every imported internal constructor/accessor. Toolchain bumps require exhaustive compile checks and differential gates.

---

## 17. Effects, commands, and foreign boundaries

### 17.1 Pure core

Reactive computation and state transition logic are pure. Browser effects are data:

```lean
inductive Cmd (Msg : Type) where
  | none
  | batch (commands : Array (Cmd Msg))
  | timeout (delayMs : UInt32) (message : Msg)
  | http (request : HttpRequest) (decode : HttpResponse → Result Error Msg)
  | storageGet ...
  | storageSet ...
  | foreign ...
```

The exact API comes later. The important invariant is that `Update` returns commands; it does not execute them.

### 17.2 Cancellation

Async commands SHOULD return typed cancellation handles owned by the component. Disposal cancels them.

Resources MUST model loading, success, failure, and cancellation explicitly. No promise rejection may escape unobserved.

### 17.3 Foreign JavaScript

Foreign code lives in explicit port modules. Each port declares:

- name;
- input and output runtime representation;
- sync/async behavior;
- cancellation behavior;
- possible errors;
- trust and security notes;
- a mock for native/reference tests;
- a browser integration test.

No application module may directly emit arbitrary JavaScript.

---

## 18. Dependent types as a UI feature

Dependent types are not merely implementation decoration. At least one dogfood example MUST demonstrate an end-user guarantee.

### 18.1 Tabs example

```lean
component Tabs (n : Nat) where
  prop labels : Vector String (n + 1)
  prop panels : Vector Panel (n + 1)

  state selected : Fin (n + 1) :=
    ⟨0, Nat.zero_lt_succ n⟩

  event select (index : Fin (n + 1)) =>
    set selected index

  view =>
    ... panels.get selected ...
```

Required guarantee:

- labels and panels have equal nonzero length;
- selected always indexes a valid panel;
- no runtime bounds check is required for the logical operation;
- length and proof fields are erased from browser representation where safe.

### 18.2 Typestate example

A later form may use indexed states:

```lean
inductive FormPhase where
  | editing
  | valid
  | submitting
  | submitted

structure LoginForm (phase : FormPhase) where
  ...
```

Only `LoginForm .valid` can enter submit. The browser representation can erase the proof index while preserving a runtime phase tag only if behavior needs it.

### 18.3 Sigma/dependent pairs

Runtime-sized collections whose size is not statically known may be packaged:

```lean
(n : Nat) × Vector Item n
```

The compiler may erase `n` when it is recoverable from the array and not observed independently.

### 18.4 Phase separation

Types may depend on compile-time values, parameters, and proof terms. They MUST NOT depend directly on mutable runtime state in a way that changes a binding’s type during execution.

Mutable value/index relationships must be packaged atomically in indexed data or existential/dependent pairs.

---

## 19. Components and composition

### 19.1 Ownership

A component owns:

- its state store;
- derived cache;
- pending bitsets/queues;
- DOM nodes;
- event listeners;
- child handles;
- commands/resources.

No global singleton scheduler is required for the PoC.

### 19.2 Props

Props are immutable per render instance in the first version. Prop updates may be added as source nodes later.

Every prop type must have a runtime representation. Proof-only props are erased.

### 19.3 Child components

Child components are deferred until single-component semantics are stable. The intended model is explicit ownership with typed input and typed emitted messages.

Parent-child graph flattening is an optimization, not an initial semantic requirement.

---

## 20. Structural delta roadmap

Scalar actual-change propagation does not make `filter` over one million rows incremental. Structural delta is a separate feature.

Later collection type:

```lean
inductive ListDelta (α : Type) where
  | insert (index : Nat) (value : α)
  | remove (index : Nat)
  | update (index : Nat) (value : α)
  | move (from to : Nat)
  | reset (values : Array α)
```

Potential staged operators:

```text
mapDelta
filterDelta
keyBy
sortDelta
foldDelta
joinDelta
```

Each operator requires a correctness statement connecting delta application to full recomputation.

The runtime may choose between delta and full recomputation using a cost model. This MUST be data-driven and benchmarked, not assumed.

---

## 21. CLI and build interface

Initial commands:

```text
lake exe leanrx -- check <Module>
lake exe leanrx -- build <Module> --out dist/
lake exe leanrx -- graph <Module> --format json|dot
lake exe leanrx -- explain <error-code>
lake exe leanrx -- doctor
```

Convenience wrapper MAY expose:

```text
leanrx check
leanrx build
leanrx test
leanrx dev
```

`check` performs elaboration, proofs, graph validation, no-escape policy, and backend support checks without writing a browser bundle.

`build` writes through a temporary directory and atomically replaces `dist/` only after success.

`graph` outputs deterministic JSON/DOT including node names, kinds, types, deps, ranks, equality plans, and source spans.

---

## 22. Testing architecture

### 22.1 Test pyramid

```text
Lean proof compilation
  + pure unit tests
  + property tests over small graphs
  + compile-pass/fail fixtures
  + IR/codegen golden tests
  + native-vs-JS differential tests
  + browser integration tests
  + performance regression tests
```

No single layer substitutes for another.

### 22.2 Pure unit tests

Test modules independently:

- dependency-set union/canonicalization;
- expression evaluation;
- dependency congruence theorem;
- update read/write behavior;
- cycle reporting;
- topological scheduling;
- affected closure;
- equality stop;
- transaction batching;
- JS identifier escaping;
- JS literal escaping;
- deterministic printer.

### 22.3 Property tests

Generate small acyclic programs with a fixed seed. Compare reference and optimized evaluation over event sequences.

Properties:

- final source store equal;
- final derived store equal;
- abstract observations equal;
- optimized node evaluations never exceed reference evaluations for the same affected model;
- unchanged derived nodes do not awaken consumers;
- node evaluation order respects rank;
- every scheduled node is reachable from a changed source.

Failing seeds become permanent fixtures.

### 22.4 Compile-fail tests

Required cases:

- mutation in `derived`;
- IO in `view`;
- unsupported browser lowering;
- reactive cycle;
- wrong event argument;
- invalid DOM property;
- missing `RuntimeRep`;
- missing lawful equality;
- `Vector` length mismatch;
- invalid unchecked numeric selection at a `Fin` boundary (public constructors
  require the original `Nat` plus a strict-bound proof; see ADR-0011);
- use of banned `sorry`/`admit` in application modules;
- direct foreign JS outside a port.

### 22.5 Golden tests

Snapshot:

- Reactive IR;
- graph JSON/DOT;
- JavaScript AST pretty output;
- generated ESM;
- stable diagnostic code/message fragments.

A golden update must be intentional and reviewed.

### 22.6 Differential gate

For the same test program and inputs:

```text
native/reference Lean result
      ==
generated JavaScript result
```

Probe at least:

- arithmetic boundaries;
- strings and Unicode;
- option/sum representation;
- structures;
- equality;
- event batching;
- derived actual-change stop;
- abstract view observations.

### 22.7 Browser tests

Use Playwright or an equivalent real-browser harness.

Required scenarios:

- mount initial DOM;
- click updates exact text/property;
- parity same-value suppression produces no parity DOM write;
- diamond graph has no intermediate DOM state;
- multiple mounts do not share state;
- nested event transaction commits once;
- dispose is idempotent;
- disposed handlers do not update;
- unsafe text is rendered as text, not HTML;
- dependent Tabs cannot select out of range through public APIs.

### 22.8 Determinism test

Build the same module twice in clean temporary directories. Byte-compare:

- graph JSON;
- generated ESM;
- source maps;
- manifest.

---

## 23. Instrumentation and performance

Development builds SHOULD expose counters:

```text
sourceWrites
derivedEvaluations
derivedChanges
sinkEvaluations
domWrites
transactions
commandsStarted
commandsCancelled
```

The Counter dogfood scenario `count: 1 → 3` should demonstrate:

```text
count changed
  doubled: 2 → 6       changed, propagate
  parity: "odd" → "odd" unchanged, stop
```

Expected parity DOM writes: `0`.

Benchmarks MUST report:

- generated bundle bytes before/after minification;
- mount time;
- update time;
- node evaluations;
- DOM writes;
- memory for graph/cache;
- build/elaboration time.

Benchmark conclusions must include negative results.

---

## 24. Security model

### 24.1 XSS

Interpolated user strings always become text nodes or context-specific safe encodings. Raw HTML requires an explicit `TrustedHtml` value that cannot be constructed from a plain string without an audited sanitizer/foreign boundary.

### 24.2 URLs

URL-bearing properties use typed wrappers where practical. `javascript:` and unsafe schemes are rejected or require an explicit unsafe capability.

### 24.3 Events

Event names and event payload adapters are whitelisted. Inline JavaScript attributes are never emitted.

### 24.4 Supply chain

- pin Lean exactly;
- commit Lake and JavaScript lockfiles;
- disable npm lifecycle scripts by default in `.npmrc`;
- keep JavaScript dependencies minimal;
- generate an SBOM or dependency report before releases;
- document any reused Qed code in `NOTICE.md`.

### 24.5 Compiler robustness

Malformed user input must produce diagnostics, not panics. Fuzz syntax/reifier boundaries where practical.

---

## 25. Trust model

### 25.1 Trusted in the PoC

- Lean kernel and trusted Lean installation;
- selected Lean standard library semantics;
- LeanRx JavaScript emitter;
- LeanRx runtime representation implementation;
- handwritten DOM host;
- browser JavaScript/DOM implementation.

### 25.2 Untrusted but checked where possible

- component elaborator;
- graph extraction;
- optimizer implementation;
- code-generation planning.

These should emit terms/certificates checked by the trusted core or be compared against reference semantics.

### 25.3 Code policy

Application and verified semantic modules MUST NOT contain:

- `sorry`;
- `admit`;
- unreviewed axioms;
- `partial` definitions in semantic paths;
- `unsafe` definitions in semantic paths.

Metaprogramming and backend modules MAY require `unsafe` Lean APIs. Such use MUST be isolated, commented, reviewed, and excluded from logical claims.

CI MUST maintain an axiom/no-sorry manifest for public theorems.

---

## 26. Lean version policy

### 26.1 Pinning

Start with:

```text
leanprover/lean4:v4.33.0
```

Do not use `latest` or a release candidate in main.

### 26.2 Upgrade process

Every Lean bump requires:

1. read release notes from current to target;
2. update `docs/upgrading-lean.md`;
3. build all Lean modules;
4. run no-sorry/axiom checks;
5. run all differential probes;
6. run browser tests;
7. byte-review generated JS and graph fixtures;
8. inspect any internal metaprogramming/compiler API changes;
9. record benchmark deltas;
10. commit the bump separately from feature work.

---

## 27. Practical dogfooding sequence

Dogfooding begins as soon as mount/update works.

| Example | Purpose | Required pressure on architecture |
|---|---|---|
| Counter | scalar graph | state, derived, event, text sinks, equality stop |
| Temperature converter | controlled input | typed DOM event, parse/result, two-way UX without cycles |
| Dependent Tabs | dependent types | `Vector`, `Fin`, erased proofs, typed event args |
| Validated form | typestate/refinement | invalid states, error rendering, submit capability |
| TodoMVC | dynamic shape | keyed rows, filter, editing state, persistence boundary |
| Notes | effects | local storage, cancellation/disposal, debouncing |
| Issue browser | async resource | HTTP, decode, loading/error/cancel, pagination |
| Data grid | performance | 10k rows, filtering, sorting, structural delta/cost model |
| LeanRx docs site | self-hosting | router, examples, production build, accessibility |

Every dogfood app MUST:

- import only public LeanRx APIs;
- compile in CI;
- have browser smoke tests;
- record friction in `DOGFOOD.md`;
- turn every framework bug into a regression test;
- forbid hand-written reactive JavaScript shortcuts;
- include an instrumentation snapshot for its defining scenario.

---

## 28. Accessibility

The view DSL SHOULD encode accessibility-relevant distinctions where feasible:

- typed `label`/`for` relationships;
- button vs clickable generic element;
- required alt text policy for informative images;
- focus and keyboard event support;
- ARIA names as typed/whitelisted attributes;
- compile warnings for common invalid patterns.

Dogfood examples must pass an automated accessibility smoke scan, while acknowledging that automated checks are incomplete.

---

## 29. Error taxonomy

Stable prefixes:

```text
LRX-SYN-*   syntax
LRX-ELAB-*  elaboration/reification
LRX-TYPE-*  representability/equality/type contracts
LRX-GRAPH-* dependency/cycle/schedule
LRX-VIEW-*  DOM/view
LRX-BE-*    backend/codegen
LRX-PORT-*  foreign/effect boundary
LRX-PROOF-* proof/certificate
```

Errors are public API. Tests should lock codes and essential explanations.

---

## 30. Definition of Done for the PoC

The PoC is complete only when all items are true.

### Language and compiler

- [ ] `component`, `state`, `derived`, `event`, and minimal JSX-like `view` compile.
- [ ] Dependency sets are kernel-checked or certificate-checked.
- [ ] Cycles are rejected with path diagnostics.
- [ ] Graph JSON/DOT is deterministic.
- [ ] Unsupported Lean expressions fail loudly.

### Semantics and proofs

- [ ] A reference evaluator exists.
- [ ] An optimized actual-change evaluator exists.
- [ ] The abstract finite-DAG equivalence theorem is complete without `sorry`.
- [ ] Transaction batching and diamond behavior are covered.

### Browser backend

- [ ] Counter emits standalone ESM plus the tiny host.
- [ ] No runtime dependency discovery exists.
- [ ] Static DOM mounts once and scalar sinks update directly.
- [ ] Disposal is idempotent.
- [ ] Generated output is deterministic.

### Dependent types

- [ ] Dependent Tabs demonstrates equal-length labels/panels and safe selection.
- [ ] Browser lowering erases proof-only data appropriately.
- [ ] Compile-fail fixtures demonstrate impossible invalid calls.

### Quality

- [ ] Unit, property, compile-fail, golden, differential, and browser tests pass.
- [ ] Counter parity scenario records zero unnecessary parity DOM writes.
- [ ] At least three practical PoC dogfood apps exist: Counter, Diamond Lab,
  Dependent Tabs. Temperature Converter remains the first M7 continuation app
  (see ADR-0012).
- [ ] `DOGFOOD.md`, `STATUS.md`, ADRs, and upgrade notes are current.
- [ ] Commit history is incremental and bisectable.
- [ ] No application or proof module contains `sorry`, `admit`, or unreviewed axioms.

---

## 31. Open research questions

These are intentionally not silently resolved by implementation accident.

1. Should the staged expression language remain first-order or gain typed closures?
2. How much ordinary Lean should `@[leanrx_inline]` unfold before diagnostics and compile time degrade?
3. Should dependency sets index terms directly, or should a smaller proof of dependency completeness accompany an unindexed AST?
4. What is the best proof-producing topological-sort design for compile-time ergonomics?
5. How should equality and change representations interact for large structures?
6. When is structural delta cheaper than recomputation?
7. Can component graphs be flattened without harming modular compilation?
8. How should async resources participate in transactions and cancellation?
9. Can generated JavaScript carry a compact certificate checked by a second independent tool?
10. Is a limited Lean compiler-IR bridge worth its version-maintenance cost?

Each resolved question requires an ADR.

---

## 32. Sources and references

Primary references to inspect during implementation:

- Lean Language Reference — elaborators, macros, compilation, Lake, type system: <https://lean-lang.org/doc/reference/latest/>
- Lean 4 release notes and exact stable versions: <https://lean-lang.org/doc/reference/latest/releases/>
- Qed repository, MIT-licensed prior art for Lean frontend development and Lean IR → JavaScript: <https://github.com/JacobAsmuth/qed>
- Qed `Js/Backend.lean`, especially its documented Lean-version-dependent surface: <https://github.com/JacobAsmuth/qed/blob/main/Js/Backend.lean>
- Qed repository layout and test/dogfood approach: <https://github.com/JacobAsmuth/qed/blob/main/README.md>

Secondary conceptual references SHOULD be added to `docs/prior-art/` with precise summaries and no copied text beyond license-compatible use.

---

## 33. One-sentence architecture

> LeanRx elaborates a restricted, dependently typed Lean UI DSL into a kernel-checked static reactive graph, proves or certifies its optimized actual-change schedule against full recomputation, and emits deterministic direct-DOM JavaScript through a small explicit backend and host boundary.
