#!/usr/bin/env bash
set -euo pipefail

first="$(mktemp -d)"
second="$(mktemp -d)"
trap 'rm -rf -- "$first" "$second"' EXIT

lake exe leanrx_generate_differential -- "$first"
lake exe leanrx_generate_differential -- "$second"

diff -ru "$first" "$second"
node Test/js/differential.mjs "$first"
