# ADR-0025: Print JavaScript expressions by operator precedence and drop effect-only returns

- Status: Accepted
- Date: 2026-08-23

## Context

The JavaScript AST printer (`LeanRx/Backend/JsPrinter.lean`) wrapped every
unary, binary, and conditional expression in parentheses, so the generated
part of every artifact read `(a[1] + 1n)`, `(!(a === b))`, `((e % 10) === 0)`,
`(-1)`, and `metrics[6] = (metrics[6] + 1)`. The parentheses were never
needed: the AST is a tree, so the printer knows every operator position, and
the forms the AST models (identifiers, literals, `!`/`-`, `+ - * / %`,
`===`, `<`, `<=`, `&&`, `||`, `?:`, calls, arrays, index access) have a fixed
grammar. After ADR-0024 the js-framework-benchmark application shipped as
one compacted module of 8,122 raw / 2,887 Brotli bytes; about 300 raw bytes
of it were these parentheses, and another 170 were `return null;`
statements that the benchmark backend emitted at the end of handlers whose
results nothing reads. Both were listed as the remaining size levers that do
not tree-shake the shipped hosts.

## Decision

The printer now emits a sub-expression in parentheses only when its own
binding strength is below the strength its position requires, using the
ECMAScript precedence of the modelled forms (conditional < `||` < `&&` <
`===` < relational < additive < multiplicative < prefix unary < call/member <
primary): a binary operator's left operand needs at least its own level and
its right operand one level more (left associativity), the conditional's test
needs more than the conditional level, a callee or index target needs the
call/member level, and a negative BigInt literal counts as a prefix unary. Two
textual guards keep the token stream well formed: `-` followed by a rendering
that starts with `-` (negation of a negation, subtraction of a negative
literal) keeps the inner operand parenthesized so it cannot merge into `--`.
A statement `target = target op value` whose target is an identifier or an
index chain of identifiers and literals, and whose `op` is arithmetic, prints
as the compound assignment `target op= value`, which evaluates the same pure
reference once. The readable and compact modes differ only in whitespace, as
before; `Printer.literal (.bigint (-7))` is `-7n`.

The benchmark backend (`LeanRx/Backend/JsFrameworkBenchmark.lean`) drops the
trailing `return null` from every handler, commit, and row-update function
(their results are ignored by the delegated listener, by the dispatcher, and
by the keyed region host) and from the dispatcher's branches, whose action
slugs are distinct and whose `action` parameter is never reassigned, so the
sequential `if` statements are mutually exclusive without an early exit. The
one-statement `disposeRow` keeps its `return null` because the AST validator
rejects empty bodies (`LRX-BE-009`). The Lean models, the runtime ABI (12),
the hosts in `runtime/`, and the compactor are unchanged.

## Consequences

Every generated artifact prints without redundant parentheses and with
compound assignments; the scalar, component, region, and example goldens that
quoted parenthesized text were updated (`return input + 1n;`,
`return price * quantity;`, `if (!(state[0] === index))`). Correctness of the
precedence table is covered by the native-to-Node differential suite (49
cases × both printer modes), the AST printer golden, every example's
Playwright contract, and the js-framework-benchmark contract against the
compacted module. The benchmark application's recorded baseline moves from
9,788 raw / 3,247 upstream-style Brotli bytes to 9,341 / 3,217 (`main.mjs`
8,122 / 2,887 → 7,675 / 2,857): the parentheses and returns are worth 367 raw
/ 36 Brotli bytes, and the compound assignments a further 80 raw bytes at a
cost of 6 Brotli bytes, because the repeated `x[n]=x[n]+1` pattern compressed
well. The CPU rows are unaffected (the same statements execute in the same
order, minus one `return`); the dispatcher now compares its action string
against every slug instead of returning after the match, eight string
comparisons per click.

## Validation

`./scripts/check.sh` runs the printer and backend goldens, the differential
suite, the example artifact tests, the benchmark size gate against the
recorded baseline, and the Playwright contracts; the upstream benchmark run
records the result in `BENCHMARK.md`.
