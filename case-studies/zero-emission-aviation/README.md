# UK Zero-Emission Flight Ecosystem — an open, computation-ready reference graph

An open, SHACL-validated knowledge graph of the UK hydrogen and electric aviation ecosystem:
organisations, airports, programmes, projects, funders, bodies, alliances and technologies, and the
relationships between them. Built by [The Tesseract Academy](https://gov.tesseract.academy) as an open
reference asset for computation-ready modelling of a fragmented innovation ecosystem.

> **Independent open reference dataset.** Compiled from public sources for demonstration of
> computation-ready ecosystem modelling. Not affiliated with, endorsed by, or a deliverable for any
> organisation named within it. Indicative maturity values are compiled from public roadmaps and
> statements, each dated, and are not an authoritative assessment. Licence: CC BY 4.0.

## Why this exists

The UK zero-emission-flight sector has strong policy signals and funding, but its data (who is building
what, who funds whom, which technologies gate which pathway) sits scattered across press releases,
programme pages and reports. That fragmentation is exactly the problem a coordination tool has to solve.
This case study shows the underlying data engineering done in the open: a typed entity model, a
controlled vocabulary, and machine-readable validation so that **only stated relationships are
represented and none are inferred**.

## What it contains (measured)

| Metric | Value |
| --- | --- |
| Entities | 42 |
| Relationships | 55 |
| RDF triples | 272 |
| SHACL violations | **0** |
| Planted dangling edge caught by validation | **yes** |

Entities by type: 15 organisations, 6 projects, 3 programmes, 3 funders, 3 bodies, 4 airports,
1 alliance, 7 technologies. Relationships span `funds`, `develops`, `partnerOf`, `memberOf`,
`usesTechnology`, `basedAt`, `demonstratesAt`, `leads`, `regulates`, `coordinates` and `feedsInto`
(the hydrogen production-to-propulsion chain).

Named entities include ATI FlyZero, Project NAPKIN, ZeroAvia, Cranfield Aerospace Solutions,
GKN Aerospace (H2GEAR, H2FlyGHT), Rolls-Royce, Airbus ZEROe, the Hydrogen in Aviation alliance,
the Jet Zero Strategy, the ATI and UKRI Future Flight Challenge, and the DfT-funded, CPC-led
Zero Emission Flight Infrastructure (ZEFI) programme.

## The validation discipline (the point)

The SHACL shapes (`shapes/zef-shapes.ttl`) enforce three things:

1. **Every entity is labelled.**
2. **Every technology carries a maturity** from a controlled list
   (Research, Development, Demonstration, Pilot, Commercial) **and a provenance string** — maturity is
   never unsourced.
3. **Referential integrity on every relationship.** The object of every ecosystem link must be a
   declared entity. This is the graph-level equivalent of "only validated, provided relationships are
   shown and none are inferred". The pipeline includes a negative test that injects a dangling edge and
   confirms the validator catches it.

## Reproduce

```bash
pip install rdflib pyshacl networkx matplotlib
python3 pipeline/build_and_validate.py
```

This builds the graph from `data/ecosystem.json`, validates it against the shapes at zero violations,
runs the negative test, and writes `graph.ttl`, `demo/graph.json`, `metrics.json` and
`assets/ecosystem-graph.png`. Open `demo/index.html` for the interactive network view.

## Files

| Path | What |
| --- | --- |
| `data/ecosystem.json` | The curated, sourced dataset (entities + relationships). |
| `ontology/zef.ttl` | The ZEF vocabulary (classes and properties). |
| `shapes/zef-shapes.ttl` | SHACL shapes (labels, maturity + provenance, referential integrity). |
| `pipeline/build_and_validate.py` | Build, validate, negative test, export graph.ttl / graph.json / PNG. |
| `graph.ttl` | The generated RDF graph. |
| `demo/index.html` | Self-contained interactive network view. |
| `assets/ecosystem-graph.png` | Static network render. |
| `metrics.json` | Machine-readable metrics. |

## How this maps to real ecosystem-coordination platforms

The same three primitives shown here (a typed stakeholder graph, a controlled-vocabulary technology
model with sourced maturity, and referential-integrity validation) are the data spine of any
"single view" coordination tool for a fragmented sector. Building them in the open, on real named
entities, is how we demonstrate the capability rather than assert it.
