#!/usr/bin/env bash
set -euo pipefail

workspace="$(mktemp -d)"
output="$workspace/dist"
diamond_output="$workspace/diamond"
tabs_output="$workspace/tabs"
temperature_output="$workspace/temperature"
validated_form_output="$workspace/validated-form"
trap 'rm -rf -- "$workspace"' EXIT

lake exe leanrx_counter_js -- "$output"
lake exe leanrx_diamond_js -- "$diamond_output"
lake exe leanrx_tabs_js -- "$tabs_output"
lake exe leanrx_temperature_js -- "$temperature_output"
lake exe leanrx_validated_form_js -- "$validated_form_output"
LEANRX_BROWSER_DIST="$output" LEANRX_DIAMOND_DIST="$diamond_output" \
  LEANRX_TABS_DIST="$tabs_output" \
  LEANRX_TEMPERATURE_DIST="$temperature_output" \
  LEANRX_VALIDATED_FORM_DIST="$validated_form_output" \
  corepack pnpm exec playwright test
