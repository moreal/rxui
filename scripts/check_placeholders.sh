#!/usr/bin/env bash
set -euo pipefail

if (( $# > 0 )); then
  roots=("$@")
else
  roots=(LeanRx.lean LeanRx Test Examples)
fi

files=()
for root in "${roots[@]}"; do
  if [[ -f "$root" && "$root" == *.lean ]]; then
    files+=("$root")
  elif [[ -d "$root" ]]; then
    while IFS= read -r file; do
      files+=("$file")
    done < <(rg --files "$root" -g '*.lean' -g '!**/fixtures/policy/**')
  fi
done

if (( ${#files[@]} == 0 )); then
  echo "placeholder policy: no Lean files in scope"
  exit 0
fi

pattern='(^|[^[:alnum:]_])(sorry|admit)([^[:alnum:]_]|$)|^[[:space:]]*(axiom|constant)[[:space:]]'
if rg --line-number --with-filename "$pattern" "${files[@]}"; then
  echo "placeholder policy: banned proof placeholder or axiom declaration found" >&2
  exit 1
fi

echo "placeholder policy: ${#files[@]} Lean files passed"
