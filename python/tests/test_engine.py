"""Engine tests. Run: pytest -q (with the package installed in the venv)."""

from open_ontologies_lite import OntologyEngine

ONT = """
@prefix ex:   <http://example.org/> .
@prefix owl:  <http://www.w3.org/2002/07/owl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

ex:Animal  a owl:Class ; rdfs:label "Animal" .
ex:Dog     a owl:Class ; rdfs:label "Dog" ; rdfs:subClassOf ex:Animal .
ex:Cat     a owl:Class .
ex:hasOwner a rdf:Property ; rdfs:domain ex:Animal ; rdfs:range ex:Person .
ex:rex     a ex:Dog .
"""


def test_validate_good():
    r = OntologyEngine.validate(ONT)
    assert r.ok and r.triples > 0 and r.error is None


def test_validate_bad():
    r = OntologyEngine.validate("@prefix : broken")
    assert not r.ok and r.error


def test_load_and_stats():
    e = OntologyEngine()
    e.load(ONT)
    s = e.stats()
    assert s["classes"] == 3          # Animal, Dog, Cat
    assert s["properties"] == 1       # hasOwner
    assert s["individuals"] == 1      # rex


def test_query_select():
    e = OntologyEngine()
    e.load(ONT)
    res = e.query(
        "SELECT ?c WHERE { ?c a <http://www.w3.org/2002/07/owl#Class> }"
    )
    assert res["type"] == "table"
    assert len(res["rows"]) == 3


def test_query_returns_values_not_none():
    e = OntologyEngine()
    e.load(ONT)
    res = e.query(
        "SELECT ?label WHERE { ?c a <http://www.w3.org/2002/07/owl#Class> ; "
        "<http://www.w3.org/2000/01/rdf-schema#label> ?label }"
    )
    labels = sorted(r["label"] for r in res["rows"])
    assert labels == ["Animal", "Dog"]   # regression: must be values, not None


def test_query_ask():
    e = OntologyEngine()
    e.load(ONT)
    res = e.query("ASK { <http://example.org/Dog> ?p ?o }")
    assert res == {"type": "boolean", "boolean": True}


def test_lint_finds_gaps():
    e = OntologyEngine()
    e.load(ONT)
    rules = {i["rule"] for i in e.lint()["issues"]}
    assert "missing-label" in rules   # ex:Cat has no label


def test_convert_roundtrip():
    out = OntologyEngine.convert(ONT, "turtle", "ntriples")
    assert "<http://example.org/Dog>" in out


def test_diff():
    a = "<http://x/A> <http://x/p> <http://x/B> ."
    b = "<http://x/A> <http://x/p> <http://x/C> ."
    d = OntologyEngine.diff(a, b, "ntriples")
    assert d["added_count"] == 1 and d["removed_count"] == 1
