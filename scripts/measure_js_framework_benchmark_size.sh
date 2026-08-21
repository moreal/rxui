#!/usr/bin/env bash
set -euo pipefail

workspace="$(mktemp -d)"
output="$workspace/dist"
trap 'rm -rf -- "$workspace"' EXIT

lake exe leanrx_js_framework_benchmark -- "$output"
node scripts/measure_js_framework_benchmark_size.mjs "$output"
