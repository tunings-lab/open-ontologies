# Contributors

Open Ontologies exists thanks to everyone who has built, used, broken, and improved it.

## Maintainer

- **Fabio Rovai** ([@fabio-rovai](https://github.com/fabio-rovai)) — project lead

## Contributors

- **Jioh L. Jung** ([@ziozzang](https://github.com/ziozzang)) — production user and contributor of substantial backend and runtime features ([PR #11](https://github.com/fabio-rovai/open-ontologies/pull/11)):
  - DuckDB SQL backbone alongside Postgres
  - OpenAI-compatible embeddings provider
  - Compile cache + TTL eviction + tool exposure filter
  - `ontology_dirs` config + `onto_repo_list` / `onto_repo_load` tools
  - Operational limits surfaced as `[section]` config
  - Docs alignment + resolver regression tests
- **Jason Smith** ([@rustforrecess](https://github.com/rustforrecess)) — diagnosed and fixed a real bug in the drift detector ([PR #14](https://github.com/fabio-rovai/open-ontologies/pull/14)):
  - Identified that anonymous restriction classes (and any blank-node IRIs returned by SPARQL) get freshly minted IDs on every parse, producing ~40 phantom add/remove pairs plus a Cartesian product of confidence-scored "renames" on `detect(x, x)` for typical OWL ontologies (Pizza tutorial repro). Shipped a surgical filter on the `_:` prefix in `extract_vocabulary` that bought time for the proper successor (RDFC 1.0 canonicalisation via Oxigraph 0.5.8 — landed in [2e329ee](https://github.com/fabio-rovai/open-ontologies/commit/2e329ee)).
  - PR description quality (clear repro, minimal diff, full checklist of build/test/clippy/audit, CHANGELOG entry) is the model contributor experience.

## How to be listed here

Open a PR. If it lands on `main` (in whole or in part), you'll be added with a short note describing your contribution. Bots and machine-generated commits are not credited as people.
