#!/usr/bin/env bash
set -euo pipefail

output="$(mktemp -d)"
trap 'rm -rf -- "$output"' EXIT

check_output="$(lake exe leanrx -- check Examples.Counter)"
if [[ "$check_output" != "Examples.Counter: ok (6 nodes)" ]]; then
  echo "leanrx check output changed: $check_output" >&2
  exit 1
fi

build_output="$(lake exe leanrx -- build Examples.Counter --out "$output")"
if [[ "$build_output" != "Examples.Counter: built $output" ]]; then
  echo "leanrx build output changed: $build_output" >&2
  exit 1
fi
node Test/js/component_artifacts.mjs "$output"

lake exe leanrx -- graph Examples.Counter > "$output/cli.graph.json"
if ! diff -u "$output/Counter.graph.json" "$output/cli.graph.json"; then
  echo "leanrx graph differs from the build artifact" >&2
  exit 1
fi

if unknown_output="$(lake exe leanrx -- check Missing.Component 2>&1)"; then
  echo "leanrx check accepted an unknown module" >&2
  exit 1
fi
if [[ "$unknown_output" != *"error[LRX-CLI-001]"* ]]; then
  echo "leanrx check returned the wrong unknown-module diagnostic" >&2
  echo "$unknown_output" >&2
  exit 1
fi

echo "LeanRx CLI checks passed"
