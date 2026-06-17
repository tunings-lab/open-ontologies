# Coverage report: PIAAC skills-mobility variable scheme

Generated 2026-06-17 by the open-ontologies engine (Oxigraph via open-ontologies-lite).

## Scheme size

- Syntactic validation: **valid**
- RDF triples loaded: **218**  (engine stats: {'triples': 218, 'classes': 0, 'properties': 0, 'individuals': 26})
- skos:Concept entities: **25**  (11 variables, 14 coded values)

## Provenance completeness (no entity invented)

- Concepts with a `prov:wasDerivedFrom` source file: **25 / 25 (100.0%)**
- Concepts carrying both a 2012 and a 2023 PIAAC source variable (cross-cycle harmonised): **13**

## Variables and their coded values

| Variable | Coded values |
| --- | ---: |
| own-edu6 | 7 |
| occ-skill | 4 |
| parental-edu | 3 |
| earn-hr-decile | 0 |
| region-tl2 | 0 |
| sex | 0 |
| final-weight | 0 |
| age10 | 0 |
| literacy-pv | 0 |
| occ-isco1 | 0 |
| numeracy-pv | 0 |

## Lint (engine quality checks)

- No lint issues: every concept has a label and a definition.

---
Reproduce: `Rscript ontology/build_scheme.R && .venv/bin/python ontology/validate_scheme.py`
