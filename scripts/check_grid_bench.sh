#!/usr/bin/env bash
set -euo pipefail

output="$(lake exe leanrx_grid_bench -- 3)"
lines="$(wc -l <<<"$output" | tr -d ' ')"
if [[ "$lines" != "3" ]] ||
    ! grep -Eq '^data-grid strategy=full iterations=3 allocations=53000 derived=56000 regionVisits=53000 deltaEdits=0 deltaModes=0 resets=0 elapsedNs=[0-9]+$' <<<"$output" ||
    ! grep -Eq '^data-grid strategy=delta iterations=3 allocations=20002 derived=1007 regionVisits=35004 deltaEdits=1007 deltaModes=7 resets=3 elapsedNs=[0-9]+$' <<<"$output" ||
    ! grep -Eq '^data-grid strategy=hybrid iterations=3 allocations=29002 derived=28004 regionVisits=29004 deltaEdits=4 deltaModes=3 resets=0 elapsedNs=[0-9]+$' <<<"$output"; then
  echo "data-grid benchmark contract changed:" >&2
  echo "$output" >&2
  exit 1
fi

echo "$output"
