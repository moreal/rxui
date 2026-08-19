#!/usr/bin/env bash
set -euo pipefail

first="$(mktemp -d)"
second="$(mktemp -d)"
trap 'rm -rf -- "$first" "$second"' EXIT

lake exe leanrx_counter_js -- "$first/dist"
lake exe leanrx_counter_js -- "$second/dist"
lake exe leanrx_diamond_js -- "$first/diamond"
lake exe leanrx_diamond_js -- "$second/diamond"

diff -ru "$first/dist/" "$second/dist/"
diff -ru "$first/diamond/" "$second/diamond/"
node --check "$first/dist/Counter.mjs"
node --check "$first/dist/leanrx_dom.mjs"
node --check "$first/dist/leanrx_host.mjs"
node Test/js/component_artifacts.mjs "$first/dist"
node --check "$first/diamond/DiamondLab.mjs"
node Test/js/diamond_artifacts.mjs "$first/diamond"
