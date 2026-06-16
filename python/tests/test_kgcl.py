"""KGCL diff tests. Run: pytest -q"""

from open_ontologies_lite import kgcl_diff

V1 = """
@prefix ex:   <http://example.org/> .
@prefix skos: <http://www.w3.org/2004/02/skos/core#> .
ex:Apple a skos:Concept ; skos:prefLabel "Apple" ; skos:definition "A pome fruit." ; skos:broader ex:Fruit .
ex:Pear  a skos:Concept ; skos:prefLabel "Pear" ; skos:broader ex:Fruit .
"""

# Changes vs V1: Pear deleted; Plum created; Apple renamed + definition changed;
# Apple's broader edge changed Fruit -> PomeFruit.
V2 = """
@prefix ex:   <http://example.org/> .
@prefix skos: <http://www.w3.org/2004/02/skos/core#> .
ex:Apple a skos:Concept ; skos:prefLabel "Apple (Malus)" ; skos:definition "A pome fruit of Malus." ; skos:broader ex:PomeFruit .
ex:Plum  a skos:Concept ; skos:prefLabel "Plum" ; skos:broader ex:Fruit .
"""


def test_kgcl_change_types():
    cs = kgcl_diff(V1, V2)
    types = {c["type"] for c in cs.changes}
    assert "node_creation" in types       # Plum
    assert "node_deletion" in types       # Pear
    assert "node_rename" in types         # Apple label
    assert "node_annotation_change" in types  # Apple definition
    assert "edge_creation" in types or "edge_deletion" in types  # broader moved


def test_kgcl_counts_and_text():
    cs = kgcl_diff(V1, V2)
    counts = cs.counts()
    assert counts.get("node_creation") == 1
    assert counts.get("node_deletion") == 1
    text = cs.to_kgcl()
    assert "create node" in text and "delete node" in text and "rename" in text


def test_kgcl_identical_is_empty():
    cs = kgcl_diff(V1, V1)
    assert cs.changes == []
