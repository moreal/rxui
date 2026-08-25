#!/usr/bin/env bash
set -euo pipefail

workspace="$(mktemp -d)"
output="$workspace/dist"
diamond_output="$workspace/diamond"
echo_output="$workspace/echo"
filter_output="$workspace/filter"
branch_output="$workspace/branch"
nest_output="$workspace/nest"
tabs_output="$workspace/tabs"
temperature_output="$workspace/temperature"
validated_form_output="$workspace/validated-form"
todo_output="$workspace/todo"
notes_output="$workspace/notes"
issue_browser_output="$workspace/issues"
grid_output="$workspace/grid"
docs_output="$workspace/docs"
trap 'rm -rf -- "$workspace"' EXIT

lake exe leanrx_counter_js -- "$output"
lake exe leanrx_diamond_js -- "$diamond_output"
lake exe leanrx_echo_js -- "$echo_output"
lake exe leanrx_filter_js -- "$filter_output"
lake exe leanrx_branch_js -- "$branch_output"
lake exe leanrx_nest_js -- "$nest_output"
lake exe leanrx_tabs_js -- "$tabs_output"
lake exe leanrx_temperature_js -- "$temperature_output"
lake exe leanrx_validated_form_js -- "$validated_form_output"
lake exe leanrx_todo_js -- "$todo_output"
lake exe leanrx_notes_js -- "$notes_output"
lake exe leanrx_issue_browser_js -- "$issue_browser_output"
lake exe leanrx_data_grid_js -- "$grid_output"
lake exe leanrx_docs_js -- "$docs_output"
LEANRX_BROWSER_DIST="$output" LEANRX_DIAMOND_DIST="$diamond_output" \
  LEANRX_ECHO_DIST="$echo_output" \
  LEANRX_FILTER_DIST="$filter_output" \
  LEANRX_BRANCH_DIST="$branch_output" \
  LEANRX_NEST_DIST="$nest_output" \
  LEANRX_TABS_DIST="$tabs_output" \
  LEANRX_TEMPERATURE_DIST="$temperature_output" \
  LEANRX_VALIDATED_FORM_DIST="$validated_form_output" \
  LEANRX_TODO_DIST="$todo_output" \
  LEANRX_NOTES_DIST="$notes_output" \
  LEANRX_ISSUE_BROWSER_DIST="$issue_browser_output" \
  LEANRX_GRID_DIST="$grid_output" \
  LEANRX_DOCS_DIST="$docs_output" \
  corepack pnpm exec playwright test --grep-invert "@grid"
# The 10k workload gets a fresh Chromium process so its DOM/GC pressure cannot
# make unrelated browser acceptance tests depend on execution order.
LEANRX_GRID_DIST="$grid_output" \
  corepack pnpm exec playwright test Test/browser/grid.spec.mjs
