#!/usr/bin/env bash
set -euo pipefail

workspace="$(mktemp -d)"
output="$workspace/dist"
trap 'rm -rf -- "$workspace"' EXIT

check_output="$(lake exe leanrx -- check Examples.Counter)"
if [[ "$check_output" != *"check Examples.Counter"* ||
      "$check_output" != *"graph: 8 nodes / 8 scheduled"* ||
      "$check_output" != *"values: 1 source / 2 derived"* ||
      "$check_output" != *"view: 5 text sinks / 4 events"* ||
      "$check_output" != *"result: ok"* ]]; then
  echo "leanrx check output changed: $check_output" >&2
  exit 1
fi

build_output="$(lake exe leanrx -- build Examples.Counter --out "$output")"
if [[ "$build_output" != *"build Examples.Counter"* ||
      "$build_output" != *"output: $output"* ||
      "$build_output" != *"publication: atomic versioned bundle"* ||
      "$build_output" != *"result: ok"* ]]; then
  echo "leanrx build output changed: $build_output" >&2
  exit 1
fi
node Test/js/component_artifacts.mjs "$output"
lake env lean "$output/Counter.generated.lean"

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

lake exe leanrx -- graph Examples.Counter --format html > "$output/cli.graph.html"
if ! diff -u "$output/Counter.graph.html" "$output/cli.graph.html"; then
  echo "leanrx HTML graph differs from the build artifact" >&2
  exit 1
fi
for fragment in "<!doctype html>" "Certified schedule:" "count" "doubled"; do
  if [[ "$(<"$output/cli.graph.html")" != *"$fragment"* ]]; then
    echo "leanrx HTML graph lost required content: $fragment" >&2
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

explain_output="$(lake exe leanrx -- explain LRX-TYPE-108)"
if [[ "$explain_output" != *"phase: typed component validation"* ||
      "$explain_output" != *"transaction barrier"* ]]; then
  echo "leanrx explain output changed: $explain_output" >&2
  exit 1
fi
if unknown_explain="$(lake exe leanrx -- explain LRX-UNKNOWN-999 2>&1)"; then
  echo "leanrx explain guessed an unknown diagnostic" >&2
  exit 1
fi
if [[ "$unknown_explain" != *"error[LRX-SYN-002]"* ]]; then
  echo "leanrx explain returned the wrong unknown-code diagnostic" >&2
  exit 1
fi

doctor_output="$(lake exe leanrx -- doctor)"
for fragment in "LeanRx doctor" "[ok] compiler: 0.1.0-dev" \
    "[ok] toolchain: leanprover/lean4:v4.33.0" "[ok] runtime ABI: 7" \
    "[ok] node:" "[ok] pnpm: 10.33.0" "[ok] browser hosts: present" \
    "[ok] backend smoke: valid" "result: ready"; do
  if [[ "$doctor_output" != *"$fragment"* ]]; then
    echo "leanrx doctor lost required result: $fragment" >&2
    exit 1
  fi
done

scaffold="$workspace/starter"
scaffold_output="$(lake exe leanrx -- scaffold --out "$scaffold")"
if [[ "$scaffold_output" != *"files: App.lean, README.md"* ||
      "$scaffold_output" != *"result: ok"* ]]; then
  echo "leanrx scaffold output changed: $scaffold_output" >&2
  exit 1
fi
lake env lean "$scaffold/App.lean"
if [[ "$(<"$scaffold/README.md")" != *"public LeanRx API"* ]]; then
  echo "leanrx scaffold README lost its public-API boundary" >&2
  exit 1
fi

echo "LeanRx CLI checks passed"
