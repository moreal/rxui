#!/usr/bin/env bash
set -euo pipefail

node --check runtime/leanrx_region.mjs
node --check runtime/leanrx_unkeyed_region.mjs
node --check runtime/leanrx_delta_region.mjs
node --check Test/js/region_contract.mjs
node Test/js/region_runtime.mjs

if rg --line-number 'currentObserver|new Proxy|eval\(|Function\(|innerHTML' \
    runtime/leanrx_region.mjs runtime/leanrx_unkeyed_region.mjs \
    runtime/leanrx_delta_region.mjs; then
  echo "dynamic region host contains a banned runtime mechanism" >&2
  exit 1
fi

# ADR-0094 H1's other half. The order contract hands each host a frozen copy of
# the caller's array, so an ordinary mutation throws inside the host call. The
# reflective writes are the ones that would fail *silently* on a frozen array
# and mutate the unfrozen one production passes, so the contract test cannot see
# them and they are banned in the host sources instead.
if rg --line-number 'Reflect\.|defineProperty|__proto__' \
    runtime/leanrx_region.mjs runtime/leanrx_unkeyed_region.mjs \
    runtime/leanrx_delta_region.mjs; then
  echo "dynamic region host writes through a reflective primitive" >&2
  exit 1
fi

echo "dynamic region host checks passed"
