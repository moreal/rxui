#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 2 && "$1" == "--" ]]; then
  output="$2"
elif [[ $# -eq 1 ]]; then
  output="$1"
else
  echo "usage: corepack pnpm docs:build -- <output>" >&2
  exit 2
fi

if [[ -z "$output" ]]; then
  echo "usage: corepack pnpm docs:build -- <output>" >&2
  exit 2
fi

lake exe leanrx_docs_js -- "$output"
