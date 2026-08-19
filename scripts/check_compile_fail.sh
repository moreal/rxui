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
  Test/fixtures/compile-fail/ClickOnlyDiv.lean
  Test/fixtures/compile-fail/UnknownEventBinding.lean
  Test/fixtures/compile-fail/ComponentRoleMismatch.lean
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
  "error[LRX-VIEW-008]"
  "error[LRX-VIEW-010]"
  "error[LRX-VIEW-005]"
  "error[LRX-VIEW-006]"
  "error[LRX-ELAB-103]"
  "error[LRX-GRAPH-001]"
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

cycle_output="$(lake env lean -E hasSorry Test/fixtures/compile-fail/ComponentCycle.lean 2>&1 || true)"
if [[ "$cycle_output" != *"a → b → a"* || "$cycle_output" != *"ComponentCycle.lean:"* ]]; then
  echo "component cycle diagnostic lost its path or source locations" >&2
  echo "$cycle_output" >&2
  exit 1
fi

binding_output="$(lake env lean -E hasSorry Test/fixtures/compile-fail/UnknownEventBinding.lean 2>&1 || true)"
if [[ "$binding_output" != *"UnknownEventBinding.lean:"* ]]; then
  echo "unknown event diagnostic lost its JSX attribute location" >&2
  echo "$binding_output" >&2
  exit 1
fi

click_output="$(lake env lean -E hasSorry Test/fixtures/compile-fail/ClickOnlyDiv.lean 2>&1 || true)"
if [[ "$click_output" != *"ClickOnlyDiv.lean:10:"* ]]; then
  echo "root JSX diagnostic lost its original element location" >&2
  echo "$click_output" >&2
  exit 1
fi

echo "compile-fail type-contract fixtures passed"
