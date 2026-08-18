#!/usr/bin/env bash
set -euo pipefail

fixtures=(
  Test/fixtures/policy/ContainsSorry.lean
  Test/fixtures/policy/ContainsAdmit.lean
  Test/fixtures/policy/PrivateAxiom.lean
  Test/fixtures/policy/PrivateConstant.lean
  Test/fixtures/policy/SetOptionAxiom.lean
  Test/fixtures/policy/NativeDecide.lean
)

for fixture in "${fixtures[@]}"; do
  if ./scripts/check_placeholders.sh "$fixture" >/dev/null 2>&1; then
    echo "placeholder scanner accepted banned fixture: $fixture" >&2
    exit 1
  fi
done

has_sorry_fixtures=(
  Test/fixtures/policy/ContainsSorry.lean
  Test/fixtures/policy/ParenthesizedSorry.lean
)

for fixture in "${has_sorry_fixtures[@]}"; do
  if lake env lean -E hasSorry "$fixture" >/dev/null 2>&1; then
    echo "Lean hasSorry gate accepted banned fixture: $fixture" >&2
    exit 1
  fi
done

./scripts/check_placeholders.sh

if ! ./scripts/check_placeholders.sh Test/fixtures/policy/AllowedWords.lean >/dev/null; then
  echo "placeholder scanner rejected harmless string/comment text" >&2
  exit 1
fi

if ./scripts/check_semantic_safety.sh Test/fixtures/policy/UnsafeSemantic.lean >/dev/null 2>&1; then
  echo "semantic safety scanner accepted an unsafe declaration" >&2
  exit 1
fi

if lake env lean Test/fixtures/policy/EnvironmentUnsafe.lean >/dev/null 2>&1; then
  echo "environment audit accepted a split unsafe declaration" >&2
  exit 1
fi

echo "placeholder scanner regression test passed"
