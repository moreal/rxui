#!/usr/bin/env bash
set -euo pipefail

bash -n scripts/*.sh
git diff --check

if rg --line-number '[[:blank:]]+$' \
    -g '*.lean' -g '*.md' -g '*.json' -g '*.yml' -g '*.yaml' -g '*.mjs' -g '*.sh'; then
  echo "format check: trailing whitespace found" >&2
  exit 1
fi

if rg --line-number $'\t' -g '*.lean'; then
  echo "format check: tab indentation found in Lean source" >&2
  exit 1
fi

echo "format and shell lint checks passed"
