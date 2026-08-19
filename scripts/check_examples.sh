#!/usr/bin/env bash
set -euo pipefail

expected=$'subtotal deps: {0,1}\nisLarge deps: {0,1,2}\nlabel deps: {0,1,2}\nfirst subtotal: 48\nfirst isLarge: true\nfirst label: large order\nsecond subtotal: 20\nsecond isLarge: false\nsecond label: small order'
actual="$(lake exe leanrx_expr_playground)"

if [[ "$actual" != "$expected" ]]; then
  echo "expression playground output changed" >&2
  echo "$actual" >&2
  exit 1
fi

echo "public examples passed"
