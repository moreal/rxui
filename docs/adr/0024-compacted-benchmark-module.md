# ADR-0024: Compact the flattened js-framework-benchmark module with a Lean tokenizer

- Status: Accepted
- Date: 2026-08-23

## Context

After ADR-0023 the js-framework-benchmark page fetched `index.html` and one
flattened `main.mjs` of 15,814 raw / 3,917 upstream-style Brotli bytes (17,480 /
4,277 for the application), against Solid's single 11,563 / 4,358-byte module.
The compressed size was already below Solid's; the uncompressed size was the
only upstream row where LeanRx still trailed it, and every CPU row was at or
below Solid within run-to-run noise. ADR-0023 kept every identifier and every
statement of the inlined hosts and left the next step undecided: a minifier
(esbuild's bundle-and-minify of the same files measures about 8.8 KB raw / 3.1
KB Brotli) would be a new build dependency that the Lean build executable would
have to shell out to, and the project has added JavaScript tooling only where a
JavaScript test needed it.

## Decision

`LeanRx/Backend/JsCompact.lean` adds a dependency-free, text-level compactor
that `lake exe leanrx_js_framework_benchmark` runs over the flattened module
(inlined hosts, compact-printed generated declarations, mount statement). The
pass tokenizes the text (words, numbers, string and template literals,
punctuators; comments dropped), classifies every word as a keyword, a property
(after `.`/`?.`, an object key, or a method name), an object shorthand member,
or a reference, and then:

- renames every top-level binding (`function`/`let`/`const`/`var` at depth
  zero) to an uppercase short name and every binding declared inside a
  top-level function (parameters, nested function names and parameters,
  `const`/`let`/`var` declarations, `catch` bindings, object-literal method
  parameters, arrow function parameters) to a lowercase short name, by
  descending use count, skipping reserved words and every free identifier of
  the module (`document`, `Math`, `String`, ...); an object shorthand member
  `{ key }` becomes `{ key: a }`; the two pools cannot collide;
- rewrites `x["name"]` to `x.name` when the literal is identifier-shaped and
  the `[` follows a value;
- prints the tokens with a space only where two tokens would otherwise merge
  (word/number pairs, `+ +`, `- -`).

It fails closed (`LRX-BE-031`) on anything it does not model: regular
expression literals, destructuring, multiple declarators in one declaration,
classes, `switch`, `with`, `yield`/`await`, `import`/`export`, `eval`/
`arguments`, computed or unsupported object members, a line break after
`return`/`throw`/`break`/`continue` or before `++`/`--`, unbalanced brackets,
and a local binding whose name is also a top-level or free identifier of the
module (the one case where renaming every occurrence of a name inside a
function could change which binding a reference resolves to). Renaming a
whole top-level function by one injective name map preserves its scoping
exactly, including shadowing between nested functions, which is why the
analysis needs no per-scope symbol table.

Nothing else changes: the readable hosts in `runtime/` remain the contract
that `leanrx doctor` checks and every other example still imports them as
separate modules; the JavaScript AST printer's compact mode is unchanged (the
compactor consumes its output and the hosts alike); no function is tree-shaken;
the runtime ABI stays at 12; the Lean models and backends are untouched.

## Consequences

The benchmark application shrinks from 17,480 to 9,788 raw bytes and from
4,277 to 3,247 upstream-style Brotli bytes (`main.mjs` 15,814 / 3,917 →
8,122 / 2,887), below Solid's module on both measures. The shipped
`main.mjs` is no longer readable; anyone reading the benchmark artifact reads
`runtime/` and the generated readable module instead. The compactor is a
second, heuristic text pass that the JavaScript AST validator does not cover,
so its correctness rests on the fail-closed rules above, a Lean golden test
(`Test/Backend/JsCompact.lean`: fixture, determinism, name pool, and
rejection cases), `node --check`, and the Playwright contract tests that the
benchmark gate runs against the compacted module. A one-off JavaScript
prototype of the same algorithm produced byte-identical output for the
benchmark module and was used only to choose the rules; it is not part of the
repository.

## Validation

`./scripts/check.sh` runs the compactor's golden test, builds the benchmark
bundle, syntax-checks `main.mjs`, compares the size report with the recorded
baseline (`bench/js-framework-benchmark-size-baseline.json`), and runs the
three contract tests; the upstream benchmark run records the result in
`BENCHMARK.md`.
