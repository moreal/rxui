#!/usr/bin/env bash
set -euo pipefail

output="$(mktemp -d)"
trap 'rm -rf -- "$output"' EXIT

lake exe leanrx_counter_js -- "$output"
LEANRX_BROWSER_DIST="$output" corepack pnpm exec playwright test
