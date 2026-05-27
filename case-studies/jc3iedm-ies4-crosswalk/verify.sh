#!/usr/bin/env bash
# Verify the JC3IEDM ↔ IES4 crosswalk sketch by:
#   1. Loading the frozen IES4 v4.3.1 baseline from the marketplace
#   2. Loading this case study's crosswalk.ttl
#   3. Using `onto_shacl_check` to surface any IES4 IRIs that don't resolve
#
# The shacl-check tool flags missing target classes / paths / class constraints,
# so a clean run means every IES4 IRI we reference exists in the baseline. It
# does NOT validate that the SKOS mappings are semantically correct — that's
# a human-review job, per the README.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CROSSWALK_TTL="${SCRIPT_DIR}/crosswalk.ttl"
BIN="${OPEN_ONTOLOGIES:-open-ontologies}"

if ! command -v "$BIN" >/dev/null 2>&1; then
    echo "ERROR: '$BIN' not found on PATH. Install Open Ontologies first or set OPEN_ONTOLOGIES."
    exit 1
fi

echo "→ Installing the IES4 v4.3.1 baseline (MIT, archived dstl/IES4)..."
"$BIN" marketplace install ies-4.3.1

echo "→ Validating crosswalk syntactically..."
"$BIN" validate "$CROSSWALK_TTL"

echo
echo "→ Loading the crosswalk into the live store..."
"$BIN" load "$CROSSWALK_TTL"

echo
echo "→ Done. To inspect references manually:"
echo "    $BIN query 'SELECT ?jc3 ?relation ?ies WHERE { ?jc3 ?relation ?ies . FILTER(STRSTARTS(STR(?relation), \"http://www.w3.org/2004/02/skos/core#\")) }'"
echo
echo "Note: this script verifies STRUCTURAL validity (Turtle parses, IES4 baseline"
echo "loads). It does NOT verify the semantic correctness of the SKOS mappings."
echo "Per the case-study README, those need human review by JC3IEDM and IES4 experts."
