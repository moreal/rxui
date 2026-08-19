#!/usr/bin/env bash
set -euo pipefail

expected=$'subtotal deps: {0,1}\nisLarge deps: {0,1,2}\nlabel deps: {0,1,2}\nfirst subtotal: 48\nfirst isLarge: true\nfirst label: large order\nsecond subtotal: 20\nsecond isLarge: false\nsecond label: small order'
actual="$(lake exe leanrx_expr_playground)"

if [[ "$actual" != "$expected" ]]; then
  echo "expression playground output changed" >&2
  echo "$actual" >&2
  exit 1
fi

graph_expected=$'node 0 count source rank=0 deps=[]\nnode 1 left derived rank=1 deps=[0]\nnode 2 right derived rank=1 deps=[0]\nnode 3 total derived rank=2 deps=[1,2]\nnode 4 totalText sink rank=3 deps=[3]\nedge 0->1\nedge 0->2\nedge 1->3\nedge 2->3\nedge 3->4\nreference total=19 derived=3 sinks=1\noptimized total=19 derived=3 sinks=1\nparity count 1->3\nparity odd->odd\nparity work reference=4 optimized=1'
graph_actual="$(lake exe leanrx_graph_lab)"

if [[ "$graph_actual" != "$graph_expected" ]]; then
  echo "graph laboratory output changed" >&2
  echo "$graph_actual" >&2
  exit 1
fi

echo "public examples passed"
