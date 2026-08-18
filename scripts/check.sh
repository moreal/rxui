#!/usr/bin/env bash
set -euo pipefail

lake build
lake exe leanrx_test
./scripts/check_placeholders.sh
./scripts/test_placeholder_scanner.sh
