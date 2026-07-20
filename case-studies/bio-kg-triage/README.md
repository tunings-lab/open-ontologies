# bio-kg-triage

**An ontology-grounded biomedical knowledge graph, validated: 0 hallucinated terms across a
real gene-disease KG, with a provenance-carrying hypothesis triage.**

Ungrounded RAG over the literature lets a language model assert edges with nothing checking
that the node types and predicates are real. This case study does the opposite: every edge is
typed with the real [Biolink Model](https://github.com/biolink/biolink-model) vocabulary and
passes a closed-world vocabulary gate (the [`onto_vocab_check`](../../README.md) principle)
before it enters the graph. It reuses, unchanged, the correctness gate benchmarked on
schema.org and IES4 in [onto-correctness-bench](../onto-correctness-bench/README.md), now on
the biomedical vocabulary and on real data.

Built for Encode / ARIA Challengescape items #42 (target discovery relies on manual literature
reasoning), #48 (no literature-to-KG synthesis tools) and, as an extension, #60 (fragmented AMR
evidence).

## The result

Deterministic run of [`src/pipeline.py`](src/pipeline.py) over live data (full table in
[`results/SUMMARY.md`](results/SUMMARY.md), raw data in [`results/results.json`](results/results.json)):

| Knowledge graph | Triples | Biolink terms | SHACL | Closed-world violations |
|---|--:|--:|--:|--:|
| Grounded (real Biolink predicate) | 284 | 3 | conforms | **0** |
| Ungrounded (fabricated predicate) | 284 | 3 | conforms | **1** |

Built from **40 real gene-disease associations** pulled live from the **Open Targets Platform**,
typed with the **Biolink Model** (868 declared terms). The grounded KG has **0 SHACL and 0
closed-world vocabulary violations**. Swap the one real Biolink predicate
(`gene_associated_with_condition`) for a plausible-but-nonexistent one (`associated_with_disease`)
and SHACL still reports `conforms=true`, while the closed-world gate rejects it. The same open-world
hole, on the biomedical vocabulary.

## Triage

Because every edge is validated and Biolink-typed, the graph answers a ranked, provenance-carrying
query directly. Top gene-disease hypotheses by Open Targets association score
([`results/triage.md`](results/triage.md)):

| Rank | Gene | Disease | Open Targets score |
|--:|---|---|--:|
| 1 | BRAF | cardiofaciocutaneous syndrome | 0.877 |
| 2 | TP53 | Li-Fraumeni syndrome | 0.876 |
| 3 | PTEN | Cowden syndrome 1 | 0.874 |
| 4 | EGFR | non-small cell lung carcinoma | 0.853 |
| 5 | BRCA1 | breast cancer | 0.839 |

Every row is a validated triple with a source. The score is the Open Targets association score,
not a model we invented; the contribution here is the *grounding and validation*, so a triage
built on this graph cannot rank on a fabricated edge.

## Where it fits

The graph is the substrate; the model that drafts against it is our shipped
[biology-ontology language model](https://huggingface.co/fabsssss/qwen3-coder-30b-a3b-bio)
(Biolink + GO-CAM + OBO, term conformance 0 to 100%). The model proposes edges; this gate
guarantees the edges use only real terms before they are committed. Neither does the other's job.

## Reproduce

```bash
./run-demo.sh     # fetches Biolink + live Open Targets data, builds and validates the KG
```

Requires Python 3.10+ and network access (Open Targets GraphQL is queried live).

## Honest scope

See [`BUILD_REPORT.md`](BUILD_REPORT.md). In short: this grounds and validates the target-disease
layer against Open Targets and Biolink, and demonstrates the closed-world gate on real biomedical
data. It does not yet include the literature-extraction front end (PubTator3) or the AMR layer
(CARD + NCBITaxon) named in the Challengescape items; those are documented extensions, not built
here. The triage ranks on Open Targets' own score, presented with provenance, not a new scoring
method.

---

### Built by Tesseract Academy

We build the correctness and assurance layer for AI-generated knowledge graphs. If you are
extracting biomedical knowledge with LLMs and need every emitted gene, disease, or relation to be
a real, typed, checkable term, the gate above runs on your vocabulary today.

[gov.tesseract.academy](https://gov.tesseract.academy) · fabio@thetesseractacademy.com
Part of [Open Ontologies](../../README.md) · MIT · real data, real numbers.
