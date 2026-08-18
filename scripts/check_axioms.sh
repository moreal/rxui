#!/usr/bin/env bash
set -euo pipefail

lake env lean Test/AxiomManifest.lean
echo "environment audit: all LeanRx declarations passed"
