# js-framework-benchmark integration

## What this measures

LeanRx provides a keyed implementation of the standard
[`js-framework-benchmark`](https://github.com/krausest/js-framework-benchmark)
table application. The integration has two deliberately separate lanes:

1. a deterministic repository gate checks the application contract, keyed DOM
   identity, generated JavaScript syntax, disposal, and shipped size;
2. the upstream runner measures CPU duration, memory, first paint, and transfer size
   alongside vanilla, React Hooks, Preact, Vue, Solid, and Svelte in Chrome.

The application uses the checked pure Lean operation model, the typed
JavaScript AST backend, the standard full keyed-region runtime, and the standard
ten-slot instrumentation contract. It does not use the optional structural
delta path. The benchmark lowering is currently a dedicated backend module; it
is evidence for the current generated runtime rather than a claim that the
general-purpose component compiler can yet lower every collection program.

## Deterministic local gate

Install this repository's pinned browser dependencies once, then run:

```sh
corepack pnpm install --frozen-lockfile --ignore-scripts
corepack pnpm exec playwright install chromium
corepack pnpm benchmark:check
```

The gate builds into a temporary directory and checks:

- every standard button and operation, including 1,000/10,000-row creation;
- the exact table shape and Bootstrap class contract expected upstream;
- keyed node identity across swap, update, selection, and deletion;
- listener detachment and idempotent disposal;
- JavaScript syntax and the exact reviewed size baseline.

It does not assert elapsed time. It is part of `./scripts/check.sh` and CI.

Generate a persistent copy or inspect only the size report with:

```sh
lake exe leanrx_js_framework_benchmark -- .tmp/leanrx-js-framework-benchmark
corepack pnpm benchmark:size
```

The size report reads `benchmark-assets.json`, which lists only resources fetched
by the benchmark page. Common benchmark CSS, metadata, and test-only files are
excluded. For parity with the pinned upstream server, files smaller than 1 KiB
remain uncompressed and larger files use Node's default Brotli settings. Gzip
level 9 is also reported for context but is not an upstream score.

The checked baseline is:

| Scope | Raw bytes | Upstream-style Brotli bytes | Gzip-9 bytes |
|---|---:|---:|---:|
| Complete fetched application | 23,013 | 5,506 | 5,801 |

The official upstream size workload independently produced 23,013 raw bytes and
5,506 compressed bytes during integration verification.

## Prepare the official runner

The integration is pinned to upstream tag `chrome150`, commit
`fa15a77d73dca6dfc0a97ce8c4d6c0797726fa75`. The repository is fetched on
demand rather than kept as a submodule: it is a large, independently versioned
test suite with dependencies for hundreds of implementations, while LeanRx
needs one immutable runner revision.

Prepare the default `.tmp/js-framework-benchmark` checkout, runner dependencies,
and official pre-built framework artifacts once (a benchmark command also does
this automatically when they are missing):

```sh
corepack pnpm benchmark:prepare
```

An explicit checkout path may be supplied as the final argument. The script
refuses a checkout at any other commit and replaces only a previously generated
`frameworks/keyed/leanrx` directory. Preparation downloads the release's 44.8 MB
`build.zip`, verifies its pinned SHA-256 digest, and extracts the pre-built
artifacts required by React and some of the other 186 upstream implementations.
It does not install and execute every framework's dependency tree.

## Run performance measurements

For publishable measurements, close unrelated applications, disable power-saving
modes, use the normal visible Chrome mode, and run:

```sh
corepack pnpm benchmark:compare
```

The runner first executes upstream keyed and CSP checks, then benchmarks
LeanRx with `vanillajs`, `react-hooks`, `preact-hooks`, `vue`, `solid`, and
`svelte` under the same server and Chrome settings. These are all keyed
implementations; comparing a keyed implementation with a non-keyed one can
reward different DOM identity semantics.
It uses the upstream repetition count by default and builds the upstream results
table. The exact generated framework, raw JSON, Chrome traces, the table,
repository status/patch, and environment metadata are archived under
`.tmp/js-framework-benchmark-results/<UTC timestamp>/`. Publishable runs should
still use a clean committed tree.

Useful controls are:

```sh
corepack pnpm benchmark:baseline                 # LeanRx and vanilla only
corepack pnpm benchmark:compare:cpu              # nine CPU workloads only
corepack pnpm benchmark:compare:size             # size and first paint only
corepack pnpm benchmark:all-keyed                # every keyed implementation
corepack pnpm benchmark:all                      # every keyed and non-keyed implementation
./scripts/run_js_framework_benchmark.sh --framework keyed/react-hooks
./scripts/run_js_framework_benchmark.sh --benchmark 01_ --benchmark 05_
LEANRX_BENCH_COUNT=20 corepack pnpm benchmark:compare
LEANRX_BENCH_CHROME_BINARY=/path/to/chrome corepack pnpm benchmark:compare
LEANRX_BENCH_RESULTS_DIR=/path/to/archive corepack pnpm benchmark:compare
corepack pnpm benchmark:compare -- --headless --smoke
corepack pnpm benchmark:compare -- --no-results
```

`--framework` may be repeated and automatically includes `keyed/leanrx`.
`benchmark:all-keyed` is the broad apples-to-apples run; `benchmark:all` also
includes non-keyed implementations and currently takes roughly 12 hours on the
upstream maintainer's reference machine. Comparison commands that need another
framework fetch the pinned official pre-built archive automatically if it is absent. The upstream
repository contains the benchmark runner and result-table generator; it is not
merely a published-results snapshot.

`--smoke` performs one short pass through every default upstream workload. It is useful
for integration validation but too noisy and under-sampled for performance
claims. Headless and visible results should not be combined. Compare medians and
dispersion over repeated visible runs on the same idle machine, and retain the
archived environment metadata whenever reporting a result.

## Interpreting changes

Treat the upstream categories independently:

- CPU results expose operation-specific reconciliation and DOM costs;
- memory workloads detect retained nodes and listener/state leaks;
- first-paint metadata and size expose the cost paid before useful interaction;
- the local byte baseline detects bloat but does not prove faster execution.

A regression in one category must not be hidden by an aggregate score. In
particular, LeanRx currently ships the shared full region host, including code
not exercised by this application, so the size result is an honest production
artifact rather than a tree-shaken lower bound. The generated application and
browser remain inside the documented trusted computing base; only its pure Lean
state-transition semantics receive Lean-level checking.
