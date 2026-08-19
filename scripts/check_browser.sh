#!/usr/bin/env bash
set -euo pipefail

workspace="$(mktemp -d)"
output="$workspace/dist"
trap 'rm -rf -- "$workspace"' EXIT

lake exe leanrx_counter_js -- "$output"
LEANRX_BROWSER_DIST="$output" corepack pnpm exec playwright test
