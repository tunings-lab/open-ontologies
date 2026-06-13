"""Call the engine directly from Python, no MCP, no server, no Rust toolchain.

    python examples/python_usage.py

This is the "library" face of the bridge: import it, drive Oxigraph through a
few lines of Python. The same engine is what the MCP server exposes as tools.
"""

from open_ontologies_lite import OntologyEngine

ONT = """
@prefix ex:   <http://example.org/> .
@prefix owl:  <http://www.w3.org/2002/07/owl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

ex:Animal a owl:Class ; rdfs:label "Animal" .
ex:Dog    a owl:Class ; rdfs:label "Dog" ; rdfs:subClassOf ex:Animal .
ex:rex    a ex:Dog .
"""

# 1. validate before loading
print("validate:", OntologyEngine.validate(ONT))

# 2. load into an in-memory store
engine = OntologyEngine()
print("loaded triples:", engine.load(ONT))

# 3. stats
print("stats:", engine.stats())

# 4. SPARQL
rows = engine.query(
    "SELECT ?label WHERE { ?c a <http://www.w3.org/2002/07/owl#Class> ; "
    "<http://www.w3.org/2000/01/rdf-schema#label> ?label }"
)
print("class labels:", [r["label"] for r in rows["rows"]])

# 5. lint
print("lint:", engine.lint())

# 6. convert to N-Triples
print("ntriples:\n" + OntologyEngine.convert(ONT, "turtle", "ntriples").strip())
