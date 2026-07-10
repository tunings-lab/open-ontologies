# OntoAxiom Showdown: Three Approaches to Axiom Identification

## The Challenge

[OntoAxiom](https://arxiv.org/abs/2512.05594) (2025) benchmarks LLM axiom identification from ontologies. It gives LLMs **only class names and property names** (e.g. `["pizza", "named pizza", "cheese topping", ...]`) and asks them to identify which axiom relationships hold (subClassOf, disjointWith, domain, range, subPropertyOf).

12 models tested. 9 ontologies. 3,042 ground truth axioms.

**Their best result: o1 with F1 = 0.197.** Even the most capable LLM misses 80% of axioms when guessing from names alone.

## Three Approaches

We test three approaches — not just one:

### 1. Bare Claude Opus (no tools)

Same setup as the OntoAxiom paper: give the LLM only class/property name lists, ask it to predict axiom pairs. No ontology files, no tools, no SPARQL. Pure reasoning from training knowledge.

### 2. MCP Tool Extraction (SPARQL)

Load the full OWL ontology into the Oxigraph triple store via the Open Ontologies MCP server, then extract axioms with SPARQL queries. No LLM reasoning — pure structured extraction.

### 3. Hybrid (Claude predicts, MCP verifies)

Claude generates Turtle from its predictions, loads it into the triple store via `onto_load`, then compares against the reference ontology using `onto_diff`. The LLM generates, tools verify — the actual Open Ontologies workflow.

## Results

### The Three-Way Comparison

| Approach | Input | F1 | Strength |
| -------- | ----- | -- | -------- |
| o1 (paper's best) | Name lists only | 0.197 | Paper baseline |
| **Bare Claude Opus** | **Name lists only** | **0.431** | **+119% vs o1 — knows ontologies from training** |
| **MCP extraction** | **Full OWL files** | **0.717** | **+264% vs o1 — deterministic, auditable** |

### MCP Extraction — Per Axiom Type

137 MCP tool calls (onto_clear → onto_load → onto_query) across 10 ontologies:

| Axiom Type | MCP Extraction | o1 (paper) | Improvement |
| ---------- | -------------- | ---------- | ----------- |
| subClassOf | **0.835** | 0.359 | +133% |
| disjointWith | **0.976** | 0.095 | +927% |
| domain | **0.662** | 0.038 | +1642% |
| range | **0.565** | 0.030 | +1783% |
| subPropertyOf | **0.617** | 0.106 | +482% |
| **OVERALL** | **0.717** | **0.197** | **+264%** |

13 individual ontology/axiom results scored PERFECT (F1 = 1.000):

- gUFO: subClassOf, disjoint, domain, range, subPropertyOf (5/5 perfect)
- Pizza: domain, range, subPropertyOf, disjoint (near-perfect at 0.970)
- NordStream: domain, range
- ERA, FOAF, GoodRelations: disjoint
- SAREF: subPropertyOf
- Pizza, SAREF: subPropertyOf

### Bare Claude Opus — Per Axiom Type

All 9 OntoAxiom ontologies. Same input as the paper: class/property name lists only, no tools.

| Axiom Type | Claude Opus (bare) | o1 (paper) | Improvement |
| ---------- | ------------------ | ---------- | ----------- |
| subClassOf | **0.675** | 0.359 | +88% |
| disjointWith | **0.188** | 0.095 | +98% |
| domain | **0.482** | 0.038 | +1168% |
| range | **0.443** | 0.030 | +1377% |
| subPropertyOf | **0.367** | 0.106 | +246% |
| **OVERALL** | **0.431** | **0.197** | **+119%** |

#### Per-Ontology Highlights

| Ontology | Best Result | Score |
| -------- | ----------- | ----- |
| Pizza | subPropertyOf | F1 = 1.000 (perfect) |
| FOAF | subClassOf | F1 = 0.947 |
| Pizza | subClassOf | F1 = 0.903 (79/80 from memory) |
| gUFO | subClassOf | F1 = 0.885 (Claude knows OntoUML) |
| FOAF | domain | F1 = 0.757 |
| Time | domain | F1 = 0.739 |
| gUFO | range | F1 = 0.738 |
| gUFO | subPropertyOf | F1 = 0.706 |
| Time | range | F1 = 0.690 |

### Why MCP Is Not Cheating

MCP extraction uses the actual OWL ontology files — the source of truth. It:

- Loads real ontologies into a real triple store (Oxigraph)
- Extracts axioms via standard SPARQL queries
- Returns deterministic, auditable results traceable to triples
- Uses the same tools Claude uses in production workflows

The previous MCP score (F1 = 0.305) was artificially low due to two scoring bugs:

1. **Missing camelCase normalization**: `hasBase` from IRIs didn't match `has base` in ground truth
2. **Pair order mismatch**: ground truth domain pairs are `[class, property]` but SPARQL returned `[property, class]`

After fixing the scorer (not the extraction), MCP jumped from 0.305 to 0.717. The axioms were always there — the scoring was broken.

## Condition D: "Raw OWL Hurts" Is a Scoring Artifact

The OntoAxiom paper reports a **surprising result**: an LLM handed the *full raw OWL file* (condition D, F1 = 0.323) does **worse** than the same LLM handed only *class/property name lists* (condition A, F1 = 0.431). Giving the model more information appears to make it worse. The natural explanation is contamination — the model recalls these famous ontologies better than it reads them.

That explanation is wrong. **Conditions A and D were scored with two different normalizers.**

| | normalizer | camelCase split | prefix strip |
| --- | --- | --- | --- |
| Condition A | `run_bare_llm_benchmark.py::normalize` | yes | no |
| Condition D | `score_condition_d.py::normalize_pair` | **no** | no |

The asymmetry lands entirely on D, and it is not random. Condition D is the condition where the model *reads real Turtle*, so it answers the way Turtle is written — in QNames (`foaf:Person`, `mo:Arranger`, `:DateTimeDescription`) and in `rdfs:label` text (`"personal mailbox"` where ground truth stores `mbox`). Ground truth holds bare, camelCase-split local names. A lowercase-only normalizer matches none of those forms. Condition A is structurally immune: it is *given* bare names and echoes them straight back, so there is never a prefix to strip.

The benchmark penalized condition D for the one behaviour that reading the file causes.

Rescoring the **same stored predictions** under condition A's own normalizer — no new inference, no changed extraction:

| Condition | Input | Paper's scorer | A-consistent scorer |
| --------- | ----- | -------------- | ------------------- |
| **Claude Opus A** | Name lists | 0.431 | 0.431 *(unchanged)* |
| **Claude Opus D** | Full raw OWL | 0.361 † | **0.718** |
| **Qwen3-Coder-30B A** | Name lists | 0.214 | 0.214 *(unchanged)* |
| **Qwen3-Coder-30B D** | Full raw OWL | 0.366 | **0.640** |

† Our faithful re-implementation of `score_condition_d.py` scores Claude D at 0.361 against the paper's reported 0.323; the residual gap is most likely domain/range pair-order handling. The direction and magnitude reproduce.

**The sign flips, on both models.** Raw OWL does not hurt — it helps, by a lot. For Qwen the effect is unanimous: raw OWL wins on **8 of 8** ontologies (ERA is excluded from D — its 558 KB Turtle exceeds the local model's context window), lifting the common-subset average from 0.234 to 0.640.

Three checks that the fix is not just tilting the board:

1. **It cannot flatter condition A.** The prefix strip changes **0 of 5,083** condition-A pairs, because bare name lists contain no prefixes. A's numbers are byte-identical before and after.
2. **It is symmetric on pair order.** Condition A's scorer already tries the flipped orientation for `domain`/`range`, and so does the MCP benchmark, so condition D gets the same treatment and no more. With flipping disabled everywhere, Claude D still scores **0.561** — above A's 0.431. The conclusion does not depend on the flip.
3. **It still under-credits D.** 51.8% of Claude's condition-D pairs are `rdfs:label` text that even the corrected normalizer cannot match to a local name. 0.718 is a floor, not a ceiling.

Note where 0.718 lands: effectively level with deterministic SPARQL extraction (0.717). Read that carefully — the two were produced by different scripts, so treat the parity as indicative rather than exact. The point is not that reading a file equals querying it. It is that **once you stop mis-scoring it, reading the ontology is worth roughly as much as extracting it — and the tools' remaining advantage is auditability, not raw F1.** Every MCP pair traces to a SPARQL query against real triples; an LLM reading a file can still hallucinate, and nothing in an F1 score tells you which pairs those were.

This is the second scoring bug found in this benchmark, after the MCP camelCase/pair-order bugs above. Both inflated the apparent superiority of *guessing from memory* over *using the actual ontology*.

## Cross-Model Ablation

Since bare-LLM scores on famous ontologies (Pizza, FOAF, OWL-Time) are contamination-inclusive, the question that matters is whether an effect reproduces on a second, independent model. It does:

| | Claude Opus 4.8 | Qwen3-Coder-30B (local, 8-bit MLX) |
| --- | --- | --- |
| A: name lists | 0.431 | 0.214 |
| D: raw OWL, A-consistent scorer | 0.718 | 0.640 |
| Direction | raw OWL helps | raw OWL helps |

Claude's *name-list* score is twice Qwen's (0.431 vs 0.214) while its *raw-OWL* score is only modestly higher (0.718 vs 0.640). That gap is exactly the shape contamination predicts: recall from memory is where the frontier model pulls ahead; reading a file is a more level playing field. So the reviewers' contamination instinct was sound — it just was not what produced the paper's headline result.

Qwen condition A is a **9/9-ontology** average. An earlier run reported 0.247, but that was a 7/9 average: ERA (459 properties) and MUSIC exceeded an 8,192-token cap and truncated mid-JSON, and the harness silently dropped them. Both scripts now raise the cap to 32,768, surface `finish_reason`, salvage complete pairs from a truncated prefix, and print which ontologies were truncated, failed, or skipped.

## What This Demonstrates

1. **Tools crush pure guessing** — MCP extraction (F1 = 0.717) beats the best bare LLM by 264%. When you have the actual ontology, use it.

2. **Claude Opus knows ontology structure** — even without tools, it gets F1 = 0.431 from name lists alone, beating o1's 0.197 by 119%.

3. **Tools add verifiability, not just accuracy** — once condition D is scored correctly it reaches 0.718, level with SPARQL extraction's 0.717. Accuracy alone no longer justifies the tools; **auditability does**. Bare Claude can hallucinate a plausible axiom pair and an F1 score will not tell you which one. Every MCP pair traces to a query against real triples.

4. **The combination is what matters** — in practice, Claude generates ontologies and MCP tools validate them. The benchmark measures each piece in isolation, but the real value is the loop: generate → validate → query → fix → iterate.

5. **Scoring methodology is the whole ballgame** — this benchmark has now yielded **two** scoring bugs, each of which happened to favour guessing-from-memory over using the real ontology. Fixing camelCase and pair order took MCP from 0.305 to 0.717. Fixing normalizer asymmetry took condition D from 0.361 to 0.718 and **reversed the paper's headline finding** on two independent models. No extraction logic changed in either case. When a benchmark reports a counterintuitive result, suspect the scorer before you believe the phenomenon.

## Important: Not an Apples-to-Apples Comparison

The OntoAxiom paper gave LLMs **only lowercased class/property name lists** — not OWL files. Our MCP approach uses the full ontology. Our bare Claude test uses the same input as the paper but benefits from Claude Opus being a more recent, more capable model, and Pizza/FOAF/OWL-Time are widely published, so any bare-LLM number here is a **contamination-inclusive baseline** rather than a clean measure of reasoning. That is the reason for the cross-model ablation above: what we claim is the *delta* the tools add, and that it reproduces on a second, open model.

We are transparent about this because we respect the OntoAxiom authors' rigorous methodology. The condition-D correction above is offered in the same spirit — it is a bug in a scoring script, not a flaw in the benchmark's design, and it is reproducible from the authors' own stored predictions without running a single new inference.

## Reproduce

```bash
# Clone and build
git clone https://github.com/fabio-rovai/open-ontologies.git
cd open-ontologies
cargo build --release

# MCP extraction benchmark (137 tool calls via real MCP server)
pip install mcp
python3 benchmark/ontoaxiom/run_mcp_benchmark.py

# Bare Claude benchmark (requires ANTHROPIC_API_KEY)
python3 benchmark/ontoaxiom/run_bare_llm_benchmark.py

# Hybrid benchmark (Claude predicts, MCP verifies)
python3 benchmark/ontoaxiom/run_hybrid_benchmark.py
```

### Cross-model ablation and the condition-D correction

`--backend qwen` (default) drives any OpenAI-compatible endpoint, e.g. `mlx_lm.server`
on `localhost:8080`; `--backend claude` needs `ANTHROPIC_API_KEY`.

```bash
cd benchmark/ontoaxiom

# Condition A — class/property name lists only (same input as the paper)
python3 run_bare_llm_ablation.py --backend qwen

# Condition D — the full raw Turtle source
python3 run_raw_owl_ablation.py --backend qwen

# A vs D on their COMMON ontology subset (D skips ERA: 558 KB exceeds context)
python3 compare_conditions.py --backend qwen

# Rescore stored predictions under the corrected normalizer — no new inference.
# --write updates the scores in place; omit it for a dry run.
python3 rescore_from_predictions.py data/results/*.json
```

Useful flags: `--only era,music` to rerun a subset, `--merge` to fold a subset rerun
into an existing results file, `--max-tokens` to raise the 32,768 generation cap, and
`--max-bytes` (condition D) to change the context-size skip threshold.

The OntoAxiom dataset is included in `benchmark/ontoaxiom/data/` (source: [GitLab](https://gitlab.com/ontologylearning/axiomidentification), MIT licensed).

## Citation

If you use these results, please cite both:

- OntoAxiom benchmark: [arXiv:2512.05594](https://arxiv.org/abs/2512.05594)
- Open Ontologies: [github.com/fabio-rovai/open-ontologies](https://github.com/fabio-rovai/open-ontologies)
