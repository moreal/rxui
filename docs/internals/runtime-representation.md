# Runtime representation contract

The runtime ABI is closed and indexed: callers may supply a local
`RuntimeRep`, but its `RuntimeType α` index prevents mapping a source type to a
different JavaScript category.

| Lean type | Runtime code | JavaScript representation | Equality plan |
|---|---|---|---|
| `Bool` | `bool` | `boolean` | strict |
| `String` | `string` | `string` | strict |
| `Int` | `int` | `bigint` | BigInt |
| `Nat` | `nat` | non-negative `bigint` | BigInt |
| `Vector α n` | `vector<α,n>` | array of the element representation | structural |
| `Fin n` | `fin<n>` | non-negative `number` index | strict |

For `Vector`, the runtime array contains only element values: the static length
and constructor evidence are erased. For `Fin`, only the numeric value remains;
the bound and proof that the value is below it are erased. Runtime type metadata
retains the length/bound so lowering can validate a whole expression before
emission, but generated values do not carry those numbers as proof objects.
Lean-checked constructors and typed vector access are therefore part of the
safety contract; foreign callers may not manufacture unchecked indices.
`RxExpr.vectorGet` requires the vector and `Fin` expression to share the same
length index. Lowering retains that relation through typed Reactive IR and emits
one JavaScript array access; the logical operation needs no runtime bounds
branch. Native-to-Node differential cases execute the first and last valid
indices in both printer modes.

`ReactiveIR.Expr.erasureReport` traverses every closed IR constructor, records
the vector lengths and finite bounds removed by the ABI, and separately records
any operation that would inspect such evidence. The scalar emitter invokes the
fail-closed `assertErasureSafe` gate before producing a JavaScript AST. The named
theorem `erasureReport_no_inspections` establishes that every expression in the
current closed IR reports no evidence inspection; its exact reviewed axiom
footprint is `[propext]`. This proves a property of the typed IR and analyzer,
not that the trusted JavaScript printer or engine implements erasure correctly.

The M3 scalar backend emits ESM functions whose parameters and returns use the
representations above. Each input position has a declared runtime code, and the
backend rejects any Reactive IR occurrence whose index is out of bounds or whose
runtime code disagrees with that signature. It imports no Lean runtime. `Int.toString` and
`Nat.toString` lower to JavaScript `String(BigInt)` and return decimal strings.

The backend does not emit raw JavaScript operators where Lean semantics differ:

- Lean `Int` modulo is Euclidean: `(-7) % 5 = 3`; JavaScript BigInt remainder
  would produce `-2n`.
- Lean `Int` and `Nat` modulo by zero return the dividend; JavaScript BigInt
  remainder throws.
- Lean `Nat` subtraction clamps at zero.

Generated private helpers implement these differences. `Int.mod` normalizes by
the absolute divisor, so both positive and negative divisor cases agree with
Lean; a zero divisor returns the dividend. `Nat` inputs are an ABI contract:
callers must provide non-negative BigInts.

Native-to-Node differential tests cover every supported scalar primitive,
negative and above-2^53 values, both divisor signs, zero divisors, clamped
subtraction, Unicode/control strings, conditionals, and display conversion. The
modules are generated from staged `RxExpr` values, so the gate includes Core to
Reactive IR lowering, and Node executes both readable and compact printer modes.

Every emitted scalar module has deterministic adjacent JSON metadata containing
the compiler version, exact Lean toolchain, module filename, runtime ABI version,
actual allocated export, ordered source/generated input names and runtime codes,
result runtime code, and the `scalar` feature marker. The runtime ABI is currently
version 2. Toolchain or ABI upgrades must update `LeanRx/Core/Version.lean`, this
document, manifest goldens, and the full differential/determinism gates together.
Generated JavaScript remains in the documented trusted computing base; these
tests are executable evidence, not a formal backend verification claim.
`RuntimeEq.jsPlan` is derived from `RuntimeType`; callers cannot pair an object
representation with JavaScript identity equality while claiming structural Lean
equality.

The M4 component ABI is also explicit. A component manifest records the ordered
runtime code for every state-array slot, the source-prefix and derived counts,
text-sink and event counts, exact host imports, exported `mount`, graph hash,
compiler/toolchain versions, and runtime ABI. The generated module owns the
state array in schema order. M5 private event handlers receive a mount-local
context containing that state, depth-first text refs, private transaction control,
changed flags, and sink caches; they update direct text nodes through `setText`.
`mount(target)` owns the mounted root and listener-disposal closures and returns
an idempotent disposer whose instrumentation accessor copies counters and trace.
The host modules integrate DOM and
effects only: they do not discover dependencies or schedule reactive work.
