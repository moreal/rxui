#!/usr/bin/env bash
set -euo pipefail

first="$(mktemp -d)"
second="$(mktemp -d)"
trap 'rm -rf -- "$first" "$second"' EXIT

lake exe leanrx_counter_js -- "$first/dist"
lake exe leanrx_counter_js -- "$second/dist"

diff -ru "$first/dist/" "$second/dist/"
node --check "$first/dist/Counter.mjs"
node --check "$first/dist/leanrx_dom.mjs"
node --check "$first/dist/leanrx_host.mjs"
node Test/js/component_artifacts.mjs "$first/dist"
