#!/usr/bin/env bash
set -euo pipefail

lake env lean Test/AxiomManifest.lean
echo "axiom audit: all public LeanRx theorems passed"
