#!/usr/bin/env bash
# Effluent data-quality demo: validate effluent observations against the SHACL
# data-quality shapes. Passes the clean records, fails each planted fault on its
# named rule. Requires pyshacl + rdflib (pip install pyshacl).
set -euo pipefail
cd "$(dirname "$0")"

echo "== Effluent monitoring data-quality validation =="
python - <<'PY'
from pyshacl import validate
from rdflib import Graph
data = Graph()
data.parse("effluent-ontology.ttl", format="turtle")
data.parse("effluent-snapshots.ttl", format="turtle")
shapes = Graph(); shapes.parse("data-quality-shapes.ttl", format="turtle")
conforms, _, text = validate(data, shacl_graph=shapes, inference="rdfs", advanced=True)
print("conforms:", conforms, "(expected False: obs_01-03 valid, obs_04-06 faulty)")
for line in text.splitlines():
    s = line.strip()
    if s.startswith("Focus Node:") or s.startswith("Message:"):
        print("  ", s)
PY

echo
echo "== Statistical QA pass on the real Melbourne WWTP open dataset =="
echo "(downloads from Kaggle on first run; see qa_wwtp.py header)"
python qa_wwtp.py 2>/dev/null || echo "  run qa_wwtp.py with numpy+matplotlib and the CSV present"
