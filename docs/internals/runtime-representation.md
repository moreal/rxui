# Runtime representation contract

The M1 scalar ABI is closed and indexed: callers may supply a local
`RuntimeRep`, but its `RuntimeType α` index prevents mapping a source type to a
different JavaScript category.

| Lean type | Runtime code | JavaScript representation | Equality plan |
|---|---|---|---|
| `Bool` | `bool` | `boolean` | strict |
| `String` | `string` | `string` | strict |
| `Int` | `int` | `bigint` | BigInt |
| `Nat` | `nat` | non-negative `bigint` | BigInt |

The M3 scalar backend emits ESM functions whose parameters and returns use the
representations above. It imports no Lean runtime. `Int.toString` and
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
subtraction, Unicode/control strings, conditionals, and display conversion.
Generated JavaScript remains in the documented trusted computing base; these
tests are executable evidence, not a formal backend verification claim.
`RuntimeEq.jsPlan` is derived from `RuntimeType`; callers cannot pair an object
representation with JavaScript identity equality while claiming structural Lean
equality.
