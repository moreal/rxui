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

The backend must not emit raw JavaScript operators where Lean semantics differ:

- Lean `Int` modulo is Euclidean: `(-7) % 5 = 3`; JavaScript BigInt remainder
  would produce `-2n`.
- Lean `Int` and `Nat` modulo by zero return the dividend; JavaScript BigInt
  remainder throws.
- Lean `Nat` subtraction clamps at zero.

Native tests pin these vectors before M3 introduces JavaScript lowering.
`RuntimeEq.jsPlan` is derived from `RuntimeType`; callers cannot pair an object
representation with JavaScript identity equality while claiming structural Lean
equality.
