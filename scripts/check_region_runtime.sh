#!/usr/bin/env bash
set -euo pipefail

node --check runtime/leanrx_region.mjs
node Test/js/region_runtime.mjs

if rg --line-number 'currentObserver|new Proxy|eval\(|Function\(|innerHTML' runtime/leanrx_region.mjs; then
  echo "dynamic region host contains a banned runtime mechanism" >&2
  exit 1
fi

echo "dynamic region host checks passed"
