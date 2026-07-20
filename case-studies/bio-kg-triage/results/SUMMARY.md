# Results summary

Vocabulary: **Biolink Model** (868 declared terms). Associations: **Open Targets Platform** (40 real gene-disease edges, live GraphQL).

| Knowledge graph | Triples | Biolink terms used | SHACL | Closed-world violations |
|---|--:|--:|--:|--:|
| Grounded (real Biolink predicate) | 284 | 3 | conforms | **0** |
| Ungrounded (fabricated predicate) | 284 | 3 | conforms | **1** |

**Headline.** The grounded KG built from 40 real Open Targets associations has **0 SHACL violations and 0 closed-world vocabulary violations**. Swapping the one real Biolink predicate (`gene_associated_with_condition`) for a plausible-but-nonexistent one (`associated_with_disease`) leaves SHACL reporting `conforms=true`, while the closed-world gate rejects it. The correctness gate works on the biomedical vocabulary exactly as on schema.org and IES4.