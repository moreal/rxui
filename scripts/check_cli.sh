#!/usr/bin/env bash
set -euo pipefail

workspace="$(mktemp -d)"
output="$workspace/dist"
docs_output="$workspace/docs"
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

docs_check_output="$(lake exe leanrx -- check Examples.LeanRxDocs)"
if [[ "$docs_check_output" != *"graph: 7 nodes / 7 scheduled"* ||
      "$docs_check_output" != *"values: 1 source / 3 derived"* ||
      "$docs_check_output" != *"view: 3 text sinks / 7 events"* ||
      "$docs_check_output" != *"result: ok"* ]]; then
  echo "LeanRx docs check output changed: $docs_check_output" >&2
  exit 1
fi
lake exe leanrx -- build Examples.LeanRxDocs --out "$docs_output"
node Test/js/docs_artifacts.mjs "$docs_output"
lake env lean "$docs_output/LeanRxDocs.generated.lean"
lake exe leanrx -- graph Examples.LeanRxDocs --format html > "$docs_output/cli.graph.html"
if ! diff -u "$docs_output/LeanRxDocs.graph.html" "$docs_output/cli.graph.html"; then
  echo "LeanRx docs CLI graph differs from its build artifact" >&2
  exit 1
fi

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
    "[ok] toolchain: leanprover/lean4:v4.33.0" "[ok] runtime ABI: 17" \
    "[ok] node:" "[ok] pnpm: 10.33.0" "[ok] browser hosts: present" \
    "[ok] playwright: Version 1.62.1" "[ok] chromium: installed" \
    "[ok] backend smoke: valid" "result: ready"; do
  if [[ "$doctor_output" != *"$fragment"* ]]; then
    echo "leanrx doctor lost required result: $fragment" >&2
    exit 1
  fi
done

incompatible_path="$PWD/Test/fixtures/cli/incompatible:$PATH"
if incompatible_doctor="$(PATH="$incompatible_path" lake exe leanrx -- doctor 2>&1)"; then
  echo "leanrx doctor accepted incompatible browser tooling" >&2
  exit 1
fi
for fragment in "[error] node: v21.99.0" "[error] pnpm: 9.99.0" \
    "[error] playwright: Version 1.61.0" "[error] chromium: unavailable" \
    "result: not ready"; do
  if [[ "$incompatible_doctor" != *"$fragment"* ]]; then
    echo "leanrx doctor lost incompatible-tool result: $fragment" >&2
    exit 1
  fi
done

unmanaged="$workspace/unmanaged"
mkdir "$unmanaged"
if unmanaged_output="$(lake exe leanrx -- build Examples.Counter --out "$unmanaged" 2>&1)"; then
  echo "leanrx build replaced an unmanaged output" >&2
  exit 1
fi
if [[ "$unmanaged_output" != *"error[LRX-PORT-003]"* ||
      "$unmanaged_output" == *"uncaught exception"* ]]; then
  echo "leanrx build did not normalize atomic output failure: $unmanaged_output" >&2
  exit 1
fi
unmanaged_scaffold="$workspace/unmanaged-scaffold"
mkdir "$unmanaged_scaffold"
if scaffold_error="$(lake exe leanrx -- scaffold --out "$unmanaged_scaffold" 2>&1)"; then
  echo "leanrx scaffold replaced an unmanaged output" >&2
  exit 1
fi
if [[ "$scaffold_error" != *"error[LRX-PORT-003]"* ||
      "$scaffold_error" == *"uncaught exception"* ]]; then
  echo "leanrx scaffold did not normalize atomic output failure: $scaffold_error" >&2
  exit 1
fi

for code in LRX-PORT-002 LRX-PORT-003 LRX-PORT-004; do
  atomic_explain="$(lake exe leanrx -- explain "$code")"
  if [[ "$atomic_explain" != *"phase: atomic CLI publication"* ||
        "$atomic_explain" != *"next:"* ]]; then
    echo "leanrx explain lost atomic output help for $code" >&2
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
