#!/usr/bin/env bash
set -euo pipefail

first="$(mktemp -d)"
second="$(mktemp -d)"
trap 'rm -rf -- "$first" "$second"' EXIT

lake exe leanrx_counter_js -- "$first/dist"
lake exe leanrx_counter_js -- "$second/dist"
lake exe leanrx_diamond_js -- "$first/diamond"
lake exe leanrx_diamond_js -- "$second/diamond"
lake exe leanrx_tabs_js -- "$first/tabs"
lake exe leanrx_tabs_js -- "$second/tabs"
lake exe leanrx_temperature_js -- "$first/temperature"
lake exe leanrx_temperature_js -- "$second/temperature"

diff -ru "$first/dist/" "$second/dist/"
diff -ru "$first/diamond/" "$second/diamond/"
diff -ru "$first/tabs/" "$second/tabs/"
diff -ru "$first/temperature/" "$second/temperature/"
node --check "$first/dist/Counter.mjs"
node --check "$first/dist/leanrx_dom.mjs"
node --check "$first/dist/leanrx_host.mjs"
node Test/js/component_artifacts.mjs "$first/dist"
node --check "$first/diamond/DiamondLab.mjs"
node Test/js/diamond_artifacts.mjs "$first/diamond"
node --check "$first/tabs/DependentTabs.mjs"
node Test/js/tabs_artifacts.mjs "$first/tabs"
node --check "$first/temperature/TemperatureConverter.mjs"
node Test/js/temperature_artifacts.mjs "$first/temperature"
