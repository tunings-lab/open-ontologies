# verifiabench

**An un-game-able benchmark for scientific-workflow LLM reliability: grade the model with a
closed-world oracle, not a fluency check. Fluency is saturated; verified correctness is not.**

Most benchmarks for LLMs on scientific tasks grade the answer with string match or an LLM judge.
Both reward a confident, well-formed answer, so a model that emits a *plausible-but-nonexistent*
gene, ontology class or predicate can score as correct. verifiabench grades differently: every
term a model emits must **exist** in the authority (the real Biolink Model) and the output must
satisfy the task's **structural** constraints. Correctness is set-membership plus constraint
satisfaction, checked deterministically, so fluency cannot buy a point.

This is the reliable-evaluation layer Encode / ARIA Challengescape items on testing LLM reasoning
and reliability on realistic scientific workflows are asking for.

## The result

Deterministic run of [`src/verifiabench.py`](src/verifiabench.py): 30 real gene-disease facts, each
asking a model to write Biolink-typed RDF, graded by the closed-world oracle. Five open models over
a local OpenAI-compatible endpoint (full table in [`results/SUMMARY.md`](results/SUMMARY.md)):

| Model | Raw capability (fluency) | **Verified capability** | Mean term-existence | Fabricated terms |
|---|--:|--:|--:|--:|
| Qwen3-Coder-30B-A3B (8bit) | 1.00 | **1.00** | 1.00 | 0 |
| Qwen2.5-3B | 1.00 | **0.00** | 0.51 | 65 |
| Llama-3.2-3B | 1.00 | **0.00** | 0.51 | 49 |
| gemma-2-2b | 0.23 | **0.00** | 0.06 | 21 |
| Qwen2.5-0.5B | 0.00 | **0.00** | 0.00 | 0 |

**Raw capability** = produced structured Biolink-namespace RDF, what a fluency- or judge-based
benchmark would reward. **Verified capability** = a real `biolink:Gene`, a real `biolink:Disease`, a
real association predicate, and zero fabricated terms.

Three models produce structured Biolink RDF on every task (raw capability 1.00), yet two of them,
Qwen2.5-3B and Llama-3.2-3B, score **0.00 verified**: roughly half of the terms they emit do not
exist in Biolink. Only Qwen3-Coder-30B actually gets it right, 1.00 verified, 0 fabricated terms.
A benchmark that graded on fluency, or asked an LLM to judge, would rank the hallucinating models
near the top. The closed-world oracle separates them cleanly and cannot be gamed by producing
plausible but nonexistent terms.

## Why this is the ownable gap

- **Fluency and correctness are different axes.** Raw capability saturates at 1.00 for any competent
  model; verified capability ranges from 0.00 to 1.00 on the same tasks. Benchmarks that cannot see
  the difference are measuring the wrong thing.
- **The oracle is deterministic and closed-world.** A term is right if and only if it is in the
  authority and used in a valid structure. No string similarity, no LLM judge, no partial credit for
  confident nonsense. This is the [`onto_vocab_check`](../onto-correctness-bench/README.md) principle
  turned into an evaluation.
- **It is un-game-able the way that matters.** You cannot lift the score by writing more fluent RDF;
  you can only lift it by using terms that actually exist. That is exactly the property a scientific
  deployment needs from its model.
- **It validates in both directions.** A genuinely capable model (Qwen3-Coder-30B) scores 100%, so
  the oracle is not just failing everything; it is measuring a real capability the weak models lack.

## Reproduce

```bash
./run-demo.sh                       # runs the default model on a local MLX/OpenAI endpoint (:8080)
./run-demo.sh "model-a" "model-b"   # benchmark specific models
VB_API=https://your-endpoint/v1/chat/completions ./run-demo.sh "gpt-..."   # any OpenAI-compatible API
```

Requires Python 3.10+ and an OpenAI-compatible chat endpoint. The runs here used a local MLX server.

## Honest scope

See [`BUILD_REPORT.md`](BUILD_REPORT.md). This is one task family (Biolink gene-disease RDF authoring)
on one authority; the method extends unchanged to GO, ChEBI, Reactome and EDAM, which is the
documented next step toward a multi-domain suite. The 30 facts are well-established, not a held-back
secret split, so the honest use is relative comparison and a public, versioned oracle, not a secret
leaderboard. The oracle checks term existence and a coarse structure (a real Gene, a real Disease, a
real association predicate); deeper semantic correctness (right predicate for the specific relation)
is the certified-denotation direction, not measured here.

---

### Built by Tesseract Academy

We build the evaluation and assurance layer for AI that has to be right, not just fluent. If you are
choosing or deploying a model for scientific or ontology-grounded work, we can benchmark it on what
it actually gets correct.

[gov.tesseract.academy](https://gov.tesseract.academy) · fabio@thetesseractacademy.com
Part of [Open Ontologies](../../README.md) · MIT · real models, real numbers.
