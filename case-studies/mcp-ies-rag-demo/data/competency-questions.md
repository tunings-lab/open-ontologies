# Competency Questions

The questions below exercise the temporal / identity / participation patterns that distinguish 4D ontology-grounded RAG from flat document RAG. For each question, the table below shows what a Claude session with `onto_query` + the IES sample dataset can answer deterministically, vs what a vector-search-over-prose system typically gets wrong.

## Question set

### Q1 — "Who was the Bristol depot manager in 2022?"

**Ontology-grounded answer:** Alice Patel.

Walk: `?state ies:isStateOf ?person ; demo:roleIn demo:acmeBristol ; ies:inPeriod ?period`, then filter by period containing 2022-01-01..2022-12-31. The `demo:aliceAsBristolManager` state has period `2020-01-01/2023-09-30` which contains 2022; the `demo:caraAsBristolManager` state has period `2023-10-01/..` which does NOT.

**Flat-RAG failure mode:** if "Alice as Bristol manager" and "Cara as Bristol manager" both surface in the top-k retrieval, the LLM has no structural way to disambiguate by date. It either picks the more recent (often wrong) or hedges.

### Q2 — "Who participated in the March 2024 Bristol fire drill?"

**Ontology-grounded answer:** Cara Lindqvist and Dan Okonkwo (per the explicit `ies:isParticipantIn` edges on `demo:bristolFireDrillMar2024`).

Walk: `demo:bristolFireDrillMar2024 ies:isParticipantIn ?person`.

**Flat-RAG failure mode:** if a document also mentions Alice (e.g. as the former Bristol manager) in proximity to a "fire drill" sentence, vector retrieval might surface her name in the answer. The ontology's explicit participant edges make this impossible.

### Q3 — "Has Alice ever worked in Bristol?"

**Ontology-grounded answer:** Yes — `demo:aliceAsBristolManager` state covers 2020-01-01 to 2023-09-30. The state still exists in the graph after her transition to London; 4D modelling preserves historical states rather than overwriting.

**Flat-RAG failure mode:** if the current corpus describes Alice as "London operations director" (her current role), the temporal precedent might not surface unless the corpus also carries a historical document.

### Q4 — "Who held a role at Acme Bristol at any point in time?"

**Ontology-grounded answer:** Alice Patel, Cara Lindqvist, Dan Okonkwo — three distinct bearers across the union of states with `demo:roleIn demo:acmeBristol`.

**Flat-RAG failure mode:** the question requires set-union over time, which fixed-window retrieval does not naturally support.

### Q5 — "What role was Alice holding when the London restructuring was announced?"

**Ontology-grounded answer:** London operations director — the `demo:londonRestructuringNov2023` event is dated 2023-11-22, and Alice's `aliceAsLondonDirector` state runs from 2023-10-01 onward, so the state containing 2023-11-22 is the London directorship.

**Flat-RAG failure mode:** answering this requires intersecting an event's date with a role-state's period. Without ontology-grounded temporal extents, this is guesswork.

### Q6 — "Which organisations are based in Bristol?"

**Ontology-grounded answer:** `demo:acmeBristol` (and any other Organisation with locations resolving to `demo:bristol`).

A straightforward SPARQL with `?org ies:inLocation demo:bristol`. No temporal reasoning needed; included as a baseline question both systems should answer correctly.

## How to run

```bash
# Load the IES baseline + the demo dataset
open-ontologies marketplace install ies-4.3.1
open-ontologies load case-studies/mcp-ies-rag-demo/data/ies-sample.ttl

# Q1 — who was Bristol manager in 2022?
open-ontologies query '
  PREFIX ies:  <http://ies.data.gov.uk/ontology/ies4#>
  PREFIX demo: <http://example.org/ies-rag-demo/>
  SELECT ?person WHERE {
    ?state ies:isStateOf ?person ;
           demo:roleIn demo:acmeBristol ;
           ies:inPeriod/ies:periodRepresentation ?p .
    FILTER(STRSTARTS(?p, "2020") || STRSTARTS(?p, "2021") || STRSTARTS(?p, "2022") || STRSTARTS(?p, "2023-0"))
  }
'

# Q2 — March 2024 fire drill participants
open-ontologies query '
  PREFIX ies: <http://ies.data.gov.uk/ontology/ies4#>
  PREFIX demo: <http://example.org/ies-rag-demo/>
  SELECT ?person WHERE { demo:bristolFireDrillMar2024 ies:isParticipantIn ?person }
'

# Q5 — Alice's role at restructuring time
open-ontologies query '
  PREFIX ies:  <http://ies.data.gov.uk/ontology/ies4#>
  PREFIX demo: <http://example.org/ies-rag-demo/>
  SELECT ?roleLabel WHERE {
    ?state ies:isStateOf demo:alice ;
           rdfs:label ?roleLabel ;
           ies:inPeriod/ies:periodRepresentation ?p .
    FILTER(STRSTARTS(?p, "2023-10") || STRSTARTS(?p, "2023-11"))
  }
'
```

The point isn't that SPARQL is the user interface — it's that the connected LLM (Claude) generates and runs these queries via `onto_query` MCP tool, and uses the results to answer the user's natural-language question with structural certainty. Vector retrieval over the same content as prose loses the temporal extents.
