# Results summary

Authority: **Biolink Model**. Tasks: **30** real gene-disease facts, each asking a model to write Biolink-typed RDF. Oracle: **closed-world term existence + structural constraints (deterministic, no LLM judge)**.

| Model | Raw capability (fluency) | **Verified capability** | Mean term-existence | Tasks with a fabricated term | Fabricated terms |
|---|--:|--:|--:|--:|--:|
| Qwen3-Coder-30B-A3B-Instruct-8bit | 1.00 | **1.00** | 1.00 | 0/30 | 0 |
| gemma-2-2b-it-4bit | 0.23 | **0.00** | 0.06 | 7/30 | 21 |
| Qwen2.5-0.5B-Instruct-4bit | 0.00 | **0.00** | 0.00 | 0/30 | 0 |
| Qwen2.5-3B-Instruct-4bit | 1.00 | **0.00** | 0.51 | 30/30 | 65 |
| Llama-3.2-3B-Instruct-4bit | 1.00 | **0.00** | 0.51 | 30/30 | 49 |

**Raw capability** = produced structured Biolink-namespace RDF (what a fluency- or LLM-judge-based benchmark would reward). **Verified capability** = a real `biolink:Gene`, a real `biolink:Disease`, a real association predicate, and zero fabricated terms.

**Headline.** Fluency is saturated and verification is not. Three models produce structured Biolink RDF on every task (raw capability 1.00), yet two of them, Qwen2.5-3B-Instruct-4bit, Llama-3.2-3B-Instruct-4bit, score **0.00 verified**: every output invents terms (around half of all terms emitted do not exist in Biolink). Only **Qwen3-Coder-30B-A3B-Instruct-8bit** actually gets it right, 1.00 verified with 0 fabricated terms. A benchmark that graded on fluency or an LLM judge would rank the hallucinating models near the top; the closed-world oracle separates them cleanly, and cannot be gamed by producing plausible but nonexistent terms.