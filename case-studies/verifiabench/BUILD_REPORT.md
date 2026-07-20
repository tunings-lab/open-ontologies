# BUILD_REPORT: verifiabench

Honest record of the benchmark, the oracle and the limits. Numbers in `results/` are produced by
`src/verifiabench.py` at temperature 0 against a local MLX OpenAI-compatible endpoint.

## What was used (real)

- **Authority:** the Biolink Model (biolink/biolink-model), 868 declared class and slot IRIs, reused
  from the bio-kg-triage case study.
- **Tasks:** 30 well-established gene-disease facts (BRCA1/breast cancer, HTT/Huntington disease,
  CFTR/cystic fibrosis, ...). Each task prompts the model to write Biolink-typed RDF asserting the fact.
- **Models under test (local, open):** Qwen3-Coder-30B-A3B (8bit), Qwen2.5-3B, Llama-3.2-3B,
  gemma-2-2b, Qwen2.5-0.5B, all served over a local MLX server on port 8080. The runner speaks the
  OpenAI chat-completions API, so any endpoint works via `VB_API`.

## The oracle (deterministic, no LLM judge)

For each model output:
1. Strip any markdown code fence.
2. Parse the Turtle with rdflib. This resolves whatever prefix the model bound to the Biolink
   namespace (models used both `biolink:` and `bio:`), so the check is format-robust, not
   prefix-brittle. If it does not parse, fall back to prefix-resolved regex extraction.
3. Collect every predicate and every `rdf:type` object whose IRI is in the Biolink namespace.
4. **Term existence:** each such term is real iff it is in Biolink's declared set; otherwise fabricated.
5. **Structure:** does the graph have a node typed `biolink:Gene`, a node typed `biolink:Disease`,
   and at least one real Biolink association predicate.
6. **raw_ok** = produced any Biolink-namespace term (the fluency proxy). **verified_ok** = real Gene
   AND real Disease AND real association predicate AND zero fabricated terms.

Per-task outputs (including the raw model text, truncated) are saved under `results/` for inspection.

## The result, precisely

- Raw capability saturates: Qwen2.5-3B, Llama-3.2-3B and Qwen3-Coder-30B all score 1.00.
- Verified capability separates: Qwen3-Coder-30B 1.00 (0 fabricated terms); Qwen2.5-3B and
  Llama-3.2-3B 0.00 (30/30 tasks contain a fabricated term, ~50% mean term-existence); gemma-2-2b
  and Qwen2.5-0.5B produce little or no valid Biolink and score 0.00.
- Manual spot-check confirms the oracle: Qwen3-Coder-30B emits real terms
  (`biolink:Gene`, `biolink:Disease`, `biolink:causes`, `biolink:has_gene_product`) in valid
  structure; the mid models emit genuine non-terms (`biolink:has_association`, `biolink:has_role`).

## Limits of the claim (do not overstate)

1. **One task family, one authority.** Biolink gene-disease RDF authoring. The method is
   authority-agnostic (GO, ChEBI, Reactome, EDAM are drop-in), but this run does not yet cover them;
   a multi-domain suite is the next step.
2. **The facts are public, not a secret split.** 30 well-known gene-disease pairs. The honest use is
   relative model comparison and a versioned, inspectable oracle, not a hold-out leaderboard.
3. **Existence and coarse structure, not full semantics.** The oracle checks that terms exist and
   that a Gene, a Disease and a real association predicate are present. It does not check that the
   *specific* predicate is the ideal one for the relation; that is the certified-denotation direction.
4. **Small models are underserved by the strict "zero fabricated terms" rule.** A model that gets the
   structure right but emits one extra invented term scores verified=0. This is deliberate: in a
   scientific pipeline a single fabricated identifier is a real defect. It is stated, not hidden.
5. **Local quantised models.** 4-8bit MLX quantisations, not full-precision or frontier API models;
   the point is the evaluation method and the raw-vs-verified gap, which any endpoint can reproduce.

## Reproducibility

`./run-demo.sh <models...>` reruns against a live endpoint (temperature 0). Model outputs can vary
across server versions, but the raw-vs-verified separation is the stable, reproducible finding.
rdflib at build time; models as listed.
