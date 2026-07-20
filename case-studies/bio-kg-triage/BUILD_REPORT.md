# BUILD_REPORT: bio-kg-triage

Honest record of what was fetched, what was computed, and the limits of the claim. Every number
in `results/` is produced by `src/pipeline.py`; none is hand-entered.

## What was fetched (real, public)

| Source | Endpoint | Use |
|---|---|---|
| Biolink Model | raw.githubusercontent.com/biolink/biolink-model (`biolink_model.yaml`, ~518 KB) | declared vocabulary (classes + slots) = the closed set |
| Open Targets Platform | api.platform.opentargets.org/api/v4/graphql (live) | real gene-disease associations + scores |

Fetched 2026-07-20. Targets queried: EGFR, TP53, KRAS, BRCA1, PTEN, BRAF, ALK, MYC (8 real human
genes by Ensembl id); top 5 associated diseases each -> 40 associations.

## What was computed

1. **Biolink vocabulary extraction.** Classes and slots from the model YAML, mapped to their
   `biolink:` IRIs (`https://w3id.org/biolink/vocab/` + PascalCase for classes, + snake_case for
   slots). 868 declared terms. This IRI derivation is documented here because the closed-world
   check depends on it; the grounded KG uses only terms present in this derived set, and the
   fabricated term is confirmed absent from it.
2. **Grounded KG.** Each association becomes: `<gene> a biolink:Gene ; rdfs:label ... ;
   biolink:gene_associated_with_condition <disease>` and `<disease> a biolink:Disease ; rdfs:label`.
   Gene IRIs are Ensembl (identifiers.org), disease IRIs are MONDO/EFO (OBO / identifiers.org).
   Provenance (Open Targets score + source) is attached in a non-policed `ex:` namespace, so it is
   data, not a Biolink-vocabulary claim.
3. **Ungrounded variant.** Identical, but the real predicate `gene_associated_with_condition` is
   replaced by `associated_with_disease`, a plausible Biolink-looking slot that is NOT in the
   declared set (confirmed programmatically). This is the ungrounded-extraction failure mode.
4. **Validation.** SHACL (pySHACL, a realistic non-closed Gene shape requiring a label) and the
   closed-world gate (every `biolink:` predicate and `rdf:type` value must be declared).

## The result, precisely

- Grounded KG (284 triples): SHACL `conforms=true`, **0** closed-world violations.
- Ungrounded KG (284 triples): SHACL `conforms=true`, **1** closed-world violation
  (`biolink:associated_with_disease`). SHACL cannot see it; the gate rejects it.
- Triage: the 40 associations ranked by Open Targets score, each row a validated Biolink-typed
  triple with provenance.

## Limits of the claim (do not overstate)

1. **Scope is the target-disease layer.** The literature-extraction front end (PubTator3 / PubMed)
   and the AMR layer (CARD + NCBITaxon) named in Challengescape #42/#48/#60 are NOT built here.
   They are the natural next stages; this case study proves the grounding-and-validation spine they
   would feed into.
2. **The triage score is Open Targets'.** We did not build a scoring model. The contribution is
   that ranking on a *validated* graph cannot surface a fabricated edge; the score itself is a
   real external silver-truth signal, presented with provenance.
3. **IRI derivation is ours.** Biolink IRIs are reconstructed from names by a documented rule
   rather than read from a published IRI list, so the closed set is only as correct as that rule.
   The terms actually used (Gene, Disease, gene_associated_with_condition) were spot-checked against
   the model; a fuller run should validate the derivation against Biolink's own JSON-LD context.
4. **Grounded, not harvested.** The KG is built from a structured API, not from raw model output.
   Replaying the shipped `fabsssss/qwen3-coder-30b-a3b-bio` model's generated edges through this
   same gate is the honest next experiment.

## Reproducibility

`./run-demo.sh` re-fetches Biolink and re-queries Open Targets, so exact association scores may
shift as Open Targets updates; the structural result (grounded = 0 violations, ungrounded caught)
is stable. rdflib, pyshacl, pyyaml, requests at build time.
