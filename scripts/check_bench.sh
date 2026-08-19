#!/usr/bin/env bash
set -euo pipefail

output="$(lake exe leanrx_graph_bench -- 1000)"
if [[ "$output" != "small-graph iterations=1000 derived=3000 sinks=1000 suppressionReference=4 suppressionOptimized=1 elapsedNs="* ]]; then
  echo "small graph benchmark output changed: $output" >&2
  exit 1
fi

echo "$output"
