#!/usr/bin/env bash
set -euo pipefail

workspace="$(mktemp -d)"
output="$workspace/dist"
trap 'rm -rf -- "$workspace"' EXIT

lake exe leanrx_js_framework_benchmark -- "$output"
node --check "$output/LeanRx.mjs"
node scripts/measure_js_framework_benchmark_size.mjs "$output" \
  bench/js-framework-benchmark-size-baseline.json
LEANRX_JS_FRAMEWORK_BENCHMARK_DIST="$output" \
  corepack pnpm exec playwright test Test/browser/js_framework_benchmark.spec.mjs \
    --reporter=line

echo "JS framework benchmark contract passed"
