#!/usr/bin/env bash
set -euo pipefail

first="$(mktemp -d)"
second="$(mktemp -d)"
trap 'rm -rf -- "$first" "$second"' EXIT

lake exe leanrx_counter_js -- "$first"
lake exe leanrx_counter_js -- "$second"

diff -ru "$first" "$second"
node --check "$first/Counter.mjs"
node --check "$first/leanrx_dom.mjs"
node --check "$first/leanrx_host.mjs"
node Test/js/component_artifacts.mjs "$first"
