#!/usr/bin/env bash
set -euo pipefail

fixture="Test/fixtures/policy/ContainsSorry.lean"

if ./scripts/check_placeholders.sh "$fixture" >/dev/null 2>&1; then
  echo "placeholder scanner accepted its banned fixture" >&2
  exit 1
fi

./scripts/check_placeholders.sh
echo "placeholder scanner regression test passed"
