#!/usr/bin/env python3
"""Load the generated SKOS scheme into the open-ontologies engine (Oxigraph),
run coverage and provenance checks via SPARQL, and write coverage-report.md.

This is the step that makes the open-ontologies platform genuinely *applied* to
the open PIAAC data: the same Oxigraph engine that powers the project validates
and reports on the harmonisation scheme."""
import sys, os, datetime
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/Users/fabio/projects/open-ontologies/python/src")
from open_ontologies_lite import OntologyEngine

ttl_path = os.path.join(HERE, "skills-mobility-scheme.ttl")
ttl = open(ttl_path).read()

# validate syntactically, then load
vr = OntologyEngine.validate(ttl, "turtle")
eng = OntologyEngine()
n_triples = eng.load(ttl, "turtle")
stats = eng.stats()

Q = lambda s: eng.query(s)["rows"]
PRE = """PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
PREFIX prov: <http://www.w3.org/ns/prov#>
PREFIX dct: <http://purl.org/dc/terms/>\n"""

n_concepts = int(Q(PRE + "SELECT (COUNT(?c) AS ?n) WHERE { ?c a skos:Concept }")[0]["n"].split("^")[0].strip('"'))
n_vars     = len(Q(PRE + "SELECT ?c WHERE { ?c skos:topConceptOf ?s }"))
n_values   = len(Q(PRE + "SELECT ?c WHERE { ?c skos:broader ?b }"))
n_prov     = len(Q(PRE + "SELECT DISTINCT ?c WHERE { ?c a skos:Concept ; prov:wasDerivedFrom ?u }"))
# concepts carrying both a 2012 and a 2023 source notation (>=2 notations)
both_cycle = len(Q(PRE + """SELECT ?c WHERE { ?c a skos:Concept ; skos:notation ?a, ?b
                            FILTER(STR(?a) != STR(?b)) } GROUP BY ?c"""))
# variable -> count of narrower coded values
vc = Q(PRE + """SELECT ?v (COUNT(?n) AS ?k) WHERE { ?v skos:topConceptOf ?s .
               OPTIONAL { ?n skos:broader ?v } } GROUP BY ?v ORDER BY DESC(?k)""")
lint = eng.lint()

prov_pct = round(100 * n_prov / n_concepts, 1) if n_concepts else 0.0
lab = lambda iri: iri.rsplit("#", 1)[-1].rstrip(">")

lines = []
w = lines.append
w("# Coverage report: PIAAC skills-mobility variable scheme\n")
w(f"Generated {datetime.date.today().isoformat()} by the open-ontologies engine "
  f"(Oxigraph via open-ontologies-lite).\n")
w("## Scheme size\n")
w(f"- Syntactic validation: **{'valid' if vr.ok else 'INVALID'}**")
w(f"- RDF triples loaded: **{n_triples}**  (engine stats: {stats})")
w(f"- skos:Concept entities: **{n_concepts}**  ({n_vars} variables, {n_values} coded values)\n")
w("## Provenance completeness (no entity invented)\n")
w(f"- Concepts with a `prov:wasDerivedFrom` source file: **{n_prov} / {n_concepts} "
  f"({prov_pct}%)**")
w(f"- Concepts carrying both a 2012 and a 2023 PIAAC source variable "
  f"(cross-cycle harmonised): **{both_cycle}**\n")
w("## Variables and their coded values\n")
w("| Variable | Coded values |")
w("| --- | ---: |")
for r in vc:
    w(f"| {lab(r['v'])} | {r['k'].split('^')[0].strip(chr(34))} |")
w("\n## Lint (engine quality checks)\n")
if isinstance(lint, dict):
    issues = {k: v for k, v in lint.items() if v}
    if not issues:
        w("- No lint issues: every concept has a label and a definition.")
    else:
        for k, v in issues.items():
            w(f"- {k}: {len(v) if isinstance(v,(list,dict)) else v}")
w("\n---\nReproduce: `Rscript ontology/build_scheme.R && "
  ".venv/bin/python ontology/validate_scheme.py`")

open(os.path.join(HERE, "coverage-report.md"), "w").write("\n".join(lines) + "\n")
print(f"coverage-report.md written: {n_concepts} concepts, {n_triples} triples, "
      f"provenance {prov_pct}%, lint {'clean' if not any((lint or {}).values()) else 'issues'}")
