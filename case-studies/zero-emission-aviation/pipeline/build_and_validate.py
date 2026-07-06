#!/usr/bin/env python3
"""Build the UK Zero-Emission Flight ecosystem graph from ecosystem.json,
validate it against the SHACL shapes (must be 0 violations), prove the
referential-integrity shape catches a planted dangling edge, and export
graph.ttl, graph.json (for the demo) and a network PNG.

Run: python3 pipeline/build_and_validate.py
"""
import json, os, sys
from rdflib import Graph, Namespace, RDF, RDFS, Literal, URIRef, XSD
from pyshacl import validate

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZEF = Namespace("https://tesseract.academy/ns/zef#")
BASE = "https://tesseract.academy/id/zef/"

TYPE_CLASS = {
    "Organisation": ZEF.Organisation, "Airport": ZEF.Airport, "Programme": ZEF.Programme,
    "Project": ZEF.Project, "Funder": ZEF.Funder, "Body": ZEF.Body,
    "Alliance": ZEF.Alliance, "Technology": ZEF.Technology,
}
REL = {
    "funds": ZEF.funds, "develops": ZEF.develops, "partnerOf": ZEF.partnerOf,
    "memberOf": ZEF.memberOf, "basedAt": ZEF.basedAt, "demonstratesAt": ZEF.demonstratesAt,
    "usesTechnology": ZEF.usesTechnology, "leads": ZEF.leads, "regulates": ZEF.regulates,
    "coordinates": ZEF.coordinates, "feedsInto": ZEF.feedsInto,
}

def uri(local):
    return URIRef(BASE + local.replace(":", "/"))

def build_graph(data):
    g = Graph()
    g.bind("zef", ZEF)
    ids = set()
    for e in data["entities"]:
        s = uri(e["id"]); ids.add(e["id"])
        g.add((s, RDF.type, ZEF.Entity))
        g.add((s, RDF.type, TYPE_CLASS[e["type"]]))
        g.add((s, RDFS.label, Literal(e["label"], datatype=XSD.string)))
        if e.get("note"): g.add((s, RDFS.comment, Literal(e["note"])))
        if e.get("source"): g.add((s, ZEF.sourceRef, Literal(e["source"], datatype=XSD.string)))
        if e["type"] == "Technology":
            g.add((s, ZEF.maturity, Literal(e["maturity"])))
            g.add((s, ZEF.maturityProvenance, Literal(e["maturity_note"], datatype=XSD.string)))
            g.add((s, ZEF.chainStage, Literal(e.get("chainStage", ""), datatype=XSD.string)))
    for r in data["relations"]:
        g.add((uri(r["s"]), REL[r["p"]], uri(r["o"])))
    return g, ids

def run_validation(data_graph):
    shapes = Graph().parse(os.path.join(HERE, "shapes", "zef-shapes.ttl"), format="turtle")
    onto = Graph().parse(os.path.join(HERE, "ontology", "zef.ttl"), format="turtle")
    conforms, _, text = validate(data_graph, shacl_graph=shapes, ont_graph=onto,
                                 inference="rdfs", abort_on_first=False, meta_shacl=False)
    return conforms, text

def main():
    data = json.load(open(os.path.join(HERE, "data", "ecosystem.json")))
    g, ids = build_graph(data)
    n_ent = len(data["entities"]); n_rel = len(data["relations"])

    conforms, text = run_validation(g)
    print(f"Entities: {n_ent}  Relations: {n_rel}  Triples: {len(g)}")
    print(f"SHACL validation (clean data): conforms={conforms}")
    if not conforms:
        print(text); sys.exit("FAIL: clean data did not conform.")

    # Negative test: inject a dangling edge (relationship to an undeclared entity)
    # and confirm the referential-integrity shape catches it.
    g2 = Graph(); [g2.add(t) for t in g]
    g2.add((uri("org:zeroavia"), ZEF.partnerOf, uri("org:does-not-exist")))
    neg_conforms, _ = run_validation(g2)
    caught = not neg_conforms
    print(f"Negative test (planted dangling edge caught): {caught}")
    if not caught:
        sys.exit("FAIL: validator did not catch the planted dangling edge.")

    # Exports
    g.serialize(os.path.join(HERE, "graph.ttl"), format="turtle")
    export_json(data, os.path.join(HERE, "demo", "graph.json"))
    print("Wrote graph.ttl and demo/graph.json")

    # Metrics for the writeup
    from collections import Counter
    by_type = Counter(e["type"] for e in data["entities"])
    by_rel = Counter(r["p"] for r in data["relations"])
    print("By type:", dict(by_type))
    print("By relation:", dict(by_rel))
    json.dump({"entities": n_ent, "relations": n_rel, "triples": len(g),
               "shacl_violations": 0, "dangling_edge_caught": caught,
               "by_type": dict(by_type), "by_relation": dict(by_rel)},
              open(os.path.join(HERE, "metrics.json"), "w"), indent=2)

TYPE_COL = {
    "Organisation": "#2e75b6", "Airport": "#c0642a", "Programme": "#1f3864",
    "Project": "#8e44ad", "Funder": "#2f9e6f", "Body": "#555555",
    "Alliance": "#c0392b", "Technology": "#0b8a8a",
}

def export_json(data, path):
    nodes = [{"id": e["id"], "label": e["label"], "type": e["type"],
              "color": TYPE_COL[e["type"]], "note": e.get("note", ""),
              "maturity": e.get("maturity", "")} for e in data["entities"]]
    edges = [{"from": r["s"], "to": r["o"], "label": r["p"]} for r in data["relations"]]
    json.dump({"nodes": nodes, "edges": edges}, open(path, "w"), indent=1)

def render_png(data, path):
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Patch
    import networkx as nx
    G = nx.DiGraph()
    for e in data["entities"]:
        G.add_node(e["id"], label=e["label"], type=e["type"])
    for r in data["relations"]:
        G.add_edge(r["s"], r["o"], label=r["p"])
    pos = nx.spring_layout(G, k=0.9, iterations=200, seed=7)
    fig, ax = plt.subplots(figsize=(15, 11)); ax.axis("off")
    cols = [TYPE_COL[G.nodes[n]["type"]] for n in G.nodes]
    sizes = [1500 if G.nodes[n]["type"] in ("Programme", "Project", "Funder") else 950 for n in G.nodes]
    nx.draw_networkx_edges(G, pos, ax=ax, edge_color="#c9c9c9", arrows=True, arrowsize=9, width=0.9, alpha=0.8)
    nx.draw_networkx_nodes(G, pos, ax=ax, node_color=cols, node_size=sizes, edgecolors="white", linewidths=1.2)
    nx.draw_networkx_labels(G, pos, labels={n: G.nodes[n]["label"] for n in G.nodes},
                            font_size=7.2, font_color="#111", ax=ax)
    legend = [Patch(color=c, label=t) for t, c in TYPE_COL.items()]
    ax.legend(handles=legend, loc="lower left", fontsize=9, frameon=False, ncol=2)
    ax.set_title("UK Zero-Emission Flight Ecosystem  |  open, SHACL-validated reference graph  |  The Tesseract Academy",
                 fontsize=13, fontweight="bold", color="#1f3864", loc="left", pad=16)
    plt.tight_layout(); plt.savefig(path, dpi=150, bbox_inches="tight"); plt.close()
    print("Wrote", path)

if __name__ == "__main__":
    main()
    data = json.load(open(os.path.join(HERE, "data", "ecosystem.json")))
    render_png(data, os.path.join(HERE, "assets", "ecosystem-graph.png"))
