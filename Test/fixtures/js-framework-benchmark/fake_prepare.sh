#!/usr/bin/env bash
set -euo pipefail

log="${LEANRX_BENCH_TEST_LOG:?LEANRX_BENCH_TEST_LOG is required}"
printf 'prepare|%s\n' "$*" >>"$log"

upstream_directory="${!#}"
mkdir -p \
  "$upstream_directory/node_modules" \
  "$upstream_directory/server/node_modules" \
  "$upstream_directory/webdriver-ts/dist"
printf '%s\n' 'fixture' >"$upstream_directory/webdriver-ts/dist/benchmarkRunner.js"

frameworks=(
  keyed/vanillajs
  keyed/react-hooks
  keyed/preact-hooks
  keyed/vue
  keyed/solid
  keyed/svelte
  keyed/leanrx
  keyed/custom
  non-keyed/vanillajs
)
for framework in "${frameworks[@]}"; do
  target="$upstream_directory/frameworks/$framework"
  mkdir -p "$target"
  printf '%s\n' '{"name":"fixture"}' >"$target/package.json"
done
