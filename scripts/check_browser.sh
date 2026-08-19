#!/usr/bin/env bash
set -euo pipefail

workspace="$(mktemp -d)"
output="$workspace/dist"
diamond_output="$workspace/diamond"
trap 'rm -rf -- "$workspace"' EXIT

lake exe leanrx_counter_js -- "$output"
lake exe leanrx_diamond_js -- "$diamond_output"
LEANRX_BROWSER_DIST="$output" LEANRX_DIAMOND_DIST="$diamond_output" \
  corepack pnpm exec playwright test
