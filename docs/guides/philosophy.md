# Philosophy and operating model

LeanRx explores one question: what changes when a frontend language makes its
reactive dependencies, update vocabulary, runtime representation, and trust
boundary inspectable before browser code exists?

## Lean is the host, not an escape hatch

Ordinary Lean constructs schemas, typed fields, staged expressions, component
specifications, and proofs about a finite semantic subset. LeanRx does not try to
transpile arbitrary Lean to JavaScript. The controlled backend accepts a small,
versioned language and rejects everything else with source-linked diagnostics.

That restriction buys a useful property: successful browser compilation says
more than “some host code happened to generate JavaScript.” It says the program
fit the checked representation and its declared runtime ABI.

## Static dependencies are part of the value

An `RxExpr` carries a typed dependency set. Component checking turns sources,
derived values, text sinks, reflected properties, and selected attributes into a
ranked graph. No observer stack or proxy discovers edges while the application
runs.

During an event:

1. source writes enter one transaction;
2. the affected frontier is scheduled in certified rank order;
3. derived equality stops unchanged propagation;
4. sink caches suppress same-value DOM writes;
5. instrumentation records the work performed.

The graph and generated module originate from the same checked component.

## Proofs and browser evidence are different claims

Lean proofs cover the documented pure semantic subset under explicit
hypotheses. The JavaScript printer, JavaScript engine, DOM host, filesystem,
Tailwind compiler, and browser platform remain in the trusted computing base.
LeanRx tests those boundaries with deterministic artifact comparisons,
differential execution, adversarial fake hosts, Playwright, axe, and benchmarks;
it does not call those tests a proof of browser behavior.

## Safety and usability must meet

A frontend language that is safe but impractical is not useful. The repository
therefore dogfoods forms, keyed regions, effects, a 10,000-row grid, the standard
js-framework-benchmark, and this documentation site. Each case records pleasant
parts, friction, missing capabilities, bugs, accessibility, and performance in
[`DOGFOOD.md`](../../DOGFOOD.md).

The support matrix is a product feature. Missing routing, Markdown ingestion,
clipboard, and complex UI primitives remain visible until LeanRx owns them.
