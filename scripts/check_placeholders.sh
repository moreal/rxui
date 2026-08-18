#!/usr/bin/env bash
set -euo pipefail

if (( $# > 0 )); then
  roots=("$@")
else
  roots=(.)
fi

files=()
for root in "${roots[@]}"; do
  if [[ -f "$root" && "$root" == *.lean ]]; then
    files+=("$root")
  elif [[ -d "$root" ]]; then
    while IFS= read -r file; do
      files+=("$file")
    done < <(rg --files "$root" -g '*.lean' -g '!**/fixtures/**' -g '!**/compile-fail/**')
  fi
done

if (( ${#files[@]} == 0 )); then
  echo "placeholder policy: no Lean files found; refusing an empty policy scope" >&2
  exit 1
fi

pattern='^[[:space:]]*(set_option[^"\n]+[[:space:]]+in[[:space:]]+)?(@\[[^]]+\][[:space:]]*)*((private|protected|public|noncomputable|unsafe|opaque|partial)[[:space:]]+)*(axiom|constant)[[:space:]]|^[[:space:]]*(sorry|admit|native_decide)([[:space:]]|$)|(:=|=>|by|exact)[[:space:]]+(sorry|admit|native_decide)([[:space:];]|$)'
if rg --line-number --with-filename "$pattern" "${files[@]}"; then
  echo "placeholder policy: banned placeholder, axiom, or unchecked proof mechanism found" >&2
  exit 1
fi

echo "placeholder policy: ${#files[@]} Lean files passed"
