#!/usr/bin/env bash
set -euo pipefail

workspace="$(mktemp -d)"
output="$workspace/dist"
trap 'rm -rf -- "$workspace"' EXIT

check_output="$(lake exe leanrx -- check Examples.Counter)"
if [[ "$check_output" != "Examples.Counter: ok (7 nodes)" ]]; then
  echo "leanrx check output changed: $check_output" >&2
  exit 1
fi

build_output="$(lake exe leanrx -- build Examples.Counter --out "$output")"
if [[ "$build_output" != "Examples.Counter: built $output" ]]; then
  echo "leanrx build output changed: $build_output" >&2
  exit 1
fi
node Test/js/component_artifacts.mjs "$output"

lake exe leanrx -- graph Examples.Counter --format json > "$output/cli.graph.json"
if ! diff -u "$output/Counter.graph.json" "$output/cli.graph.json"; then
  echo "leanrx graph differs from the build artifact" >&2
  exit 1
fi

lake exe leanrx -- graph Examples.Counter --format dot > "$output/cli.graph.dot"
if ! diff -u "$output/Counter.graph.dot" "$output/cli.graph.dot"; then
  echo "leanrx DOT graph differs from the build artifact" >&2
  exit 1
fi
for fragment in "valueType=int" "deps=[0]" "equality=bigint" "source=examples/Counter.lean:"; do
  if [[ "$(<"$output/cli.graph.dot")" != *"$fragment"* ]]; then
    echo "leanrx DOT graph lost required metadata: $fragment" >&2
    exit 1
  fi
done

if unknown_output="$(lake exe leanrx -- check Missing.Component 2>&1)"; then
  echo "leanrx check accepted an unknown module" >&2
  exit 1
fi
if [[ "$unknown_output" != *"error[LRX-ELAB-020]"* ]]; then
  echo "leanrx check returned the wrong unknown-module diagnostic" >&2
  echo "$unknown_output" >&2
  exit 1
fi

echo "LeanRx CLI checks passed"
