#!/usr/bin/env bash
set -euo pipefail

if (( $# > 0 )); then
  roots=("$@")
else
  roots=(LeanRx/Core LeanRx/Graph LeanRx/Semantics LeanRx/Proofs LeanRx/IR LeanRx/Lower
    LeanRx/Component LeanRx/View LeanRx/Form LeanRx/Region LeanRx/Todo LeanRx/Effect
    LeanRx/Notes LeanRx/IssueBrowser examples)
fi

files=()
for root in "${roots[@]}"; do
  if [[ -f "$root" && "$root" == *.lean ]]; then
    files+=("$root")
  elif [[ -d "$root" ]]; then
    while IFS= read -r file; do
      files+=("$file")
    done < <(rg --files "$root" -g '*.lean')
  fi
done

if (( ${#files[@]} == 0 )); then
  echo "semantic safety: no semantic Lean files in scope"
  exit 0
fi

pattern='^[[:space:]]*(unsafe|partial)([[:space:]]|$)|[[:space:]]in[[:space:]]+(unsafe|partial)[[:space:]]+|^[[:space:]]*(@\[[^]]+\][[:space:]]*)*((private|protected|public|noncomputable|opaque)[[:space:]]+)*(unsafe|partial)[[:space:]]'
if rg --line-number --with-filename "$pattern" "${files[@]}"; then
  echo "semantic safety: unsafe or partial declaration found in a verified path" >&2
  exit 1
fi

echo "semantic safety: ${#files[@]} verified-path Lean files passed"
