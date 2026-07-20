# Results summary - three grounded layers

Every layer builds a KG from a REAL public source, types it with a real ontology, and runs the closed-world vocabulary gate. In every layer the grounded KG has **0 closed-world violations**, and an ungrounded twin (one fabricated term) passes SHACL but is caught by the gate.

| Layer | Source | Grounded triples | Closed-world violations | Ungrounded fake |
|---|---|--:|--:|---|
| Structured (target-disease) | Open Targets + Biolink | 284 | 0 | caught |
| Literature | PubTator3 + Biolink | 169 | 0 | caught |
| Antimicrobial resistance | CARD/ARO | 1283 | 0 | caught |

- **Structured**: 40 live Open Targets gene-disease associations, Biolink-typed.
- **Literature**: 57 gene-disease relations machine-extracted by PubTator3 from 40 PubMed abstracts; all 8 target genes carry literature edges (ALK, BRAF, BRCA1, EGFR, KRAS, MYC, PTEN, TP53).
- **AMR**: 800 of 5053 real 'confers resistance to' relationships from CARD's Antibiotic Resistance Ontology (8564 declared terms); the gate polices the ARO namespace, a third ontology.

Triage (structured layer), top hypotheses by Open Targets score, each a validated Biolink triple: see [`triage.md`](triage.md).