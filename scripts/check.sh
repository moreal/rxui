#!/usr/bin/env bash
set -euo pipefail

./scripts/check_format.sh
lake build
lake exe leanrx_test
./scripts/check_examples.sh
./scripts/check_placeholders.sh
./scripts/test_placeholder_scanner.sh
./scripts/check_axioms.sh
./scripts/check_semantic_safety.sh
