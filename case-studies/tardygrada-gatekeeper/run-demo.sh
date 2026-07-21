#!/usr/bin/env bash
# Reproduce the exhaustive verification of the proof-carrying-action gatekeeper.
# Pure Python standard library, no dependencies.
set -euo pipefail
cd "$(dirname "$0")"
python3 src/gatekeeper.py
echo; echo "See results/results.json"
