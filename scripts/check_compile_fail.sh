#!/usr/bin/env bash
set -euo pipefail

fixtures=(
  Test/fixtures/compile-fail/ForgeDepSet.lean
  Test/fixtures/compile-fail/UnsupportedRead.lean
  Test/fixtures/compile-fail/MisrepresentInt.lean
  Test/fixtures/compile-fail/ForgePlannedGraph.lean
  Test/fixtures/compile-fail/MutationInDerived.lean
  Test/fixtures/compile-fail/MissingRuntimeEq.lean
  Test/fixtures/compile-fail/UnsupportedViewExpr.lean
  Test/fixtures/compile-fail/UnknownEventAttribute.lean
  Test/fixtures/compile-fail/RawHtmlView.lean
  Test/fixtures/compile-fail/ComponentCycle.lean
)
fragments=(
  "Constructor for"
  "LeanRx.RuntimeRep HostOnly"
  "LeanRx.RuntimeType Int"
  'constructor for `LeanRx.PlannedGraph` is marked as private'
  "LeanRx.Update S"
  "LeanRx.RuntimeEq Int"
  "@LeanRx.View.scalarText"
  "error[LRX-DOM-006]"
  "error[LRX-DOM-008]"
  "error[LRX-ELAB-004]"
)

for index in "${!fixtures[@]}"; do
  fixture="${fixtures[$index]}"
  if output="$(lake env lean -E hasSorry "$fixture" 2>&1)"; then
    echo "compile-fail fixture unexpectedly succeeded: $fixture" >&2
    exit 1
  fi
  if [[ "$output" != *"${fragments[$index]}"* ]]; then
    echo "compile-fail fixture produced the wrong diagnostic: $fixture" >&2
    echo "$output" >&2
    exit 1
  fi
done

echo "compile-fail type-contract fixtures passed"
