# Claude over MCP — Walkthrough Transcript

Illustrative transcript showing a Claude session connected to Open Ontologies as an MCP server, answering all six competency questions from [`../data/competency-questions.md`](../data/competency-questions.md) using `onto_query` (and `onto_search` where it would help).

The transcript is illustrative, not literal — it shows the SHAPE of the interaction, the tool calls Claude would make, and the SPARQL it would compose. Real sessions vary in wording.

## Setup (one-time)

**User:** Load the IES4 baseline and the demo dataset.

**Claude:** Calls `onto_marketplace_install("ies-4.3.1")`, then `onto_load("case-studies/mcp-ies-rag-demo/data/ies-sample.ttl")`.

> Loaded IES 4.3.1 (5,375 triples) + the demo dataset (~80 triples). The graph now has 4 ies:Persons (Alice, Bob, Cara, Dan), 2 ies:Organisations (Acme London / Bristol), 2 ies:Locations, 5 role-states with periods, and 2 events.

---

## Q1 — "Who was the Bristol depot manager in 2022?"

**Claude:** This is a temporal-extent question. I'll find all states where the role is "Bristol manager" and intersect their periods with 2022.

Calls `onto_query`:

```sparql
PREFIX ies:  <http://ies.data.gov.uk/ontology/ies4#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX demo: <http://example.org/ies-rag-demo/>

SELECT ?person ?label ?period WHERE {
    ?state ies:isStateOf ?person ;
           demo:roleIn demo:acmeBristol ;
           ies:inPeriod/ies:periodRepresentation ?period .
    ?person rdfs:label ?label .
    # 2022 falls inside the period
    FILTER(STRSTARTS(?period, "2020")
        || STRSTARTS(?period, "2021")
        || STRSTARTS(?period, "2022")
        || (STRSTARTS(?period, "2023") && !STRSTARTS(?period, "2023-1")))
}
```

**Result:** Alice Patel (period 2020-01-01/2023-09-30).

**Claude (to user):** Alice Patel was the Bristol depot manager throughout 2022, holding that role from January 2020 to September 2023. Her successor Cara Lindqvist took over in October 2023.

> Confidence: high. The role-state's `ies:inPeriod` extent is explicit in the graph and unambiguously contains 2022.

---

## Q2 — "Who participated in the March 2024 Bristol fire drill?"

**Claude:** Direct SPARQL over the explicit `ies:isParticipantIn` edges on `demo:bristolFireDrillMar2024`.

```sparql
PREFIX ies:  <http://ies.data.gov.uk/ontology/ies4#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX demo: <http://example.org/ies-rag-demo/>

SELECT ?person ?label WHERE {
    demo:bristolFireDrillMar2024 ies:isParticipantIn ?person .
    ?person rdfs:label ?label .
}
```

**Result:** Cara Lindqvist, Dan Okonkwo.

**Claude (to user):** Two people participated: Cara Lindqvist (Bristol depot manager from October 2023) and Dan Okonkwo (Bristol depot driver since March 2021). Note that Alice Patel, who was the previous Bristol manager until September 2023, did NOT participate — the event is dated March 2024, after her transition to London.

---

## Q3 — "Has Alice ever worked in Bristol?"

**Claude:** Historical existence — ASK query.

```sparql
PREFIX ies:  <http://ies.data.gov.uk/ontology/ies4#>
PREFIX demo: <http://example.org/ies-rag-demo/>

ASK { ?state ies:isStateOf demo:alice ; demo:roleIn demo:acmeBristol . }
```

**Result:** true.

**Claude (to user):** Yes. Alice held the Bristol depot manager role from January 2020 to September 2023. She has since moved to a London operations director role, but the historical state is preserved in the graph — that's the value of 4D modelling for this kind of question.

---

## Q4 — "Who held a role at Acme Bristol at any point in time?"

**Claude:** Distinct bearers across all states with `roleIn` Acme Bristol.

```sparql
PREFIX ies:  <http://ies.data.gov.uk/ontology/ies4#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX demo: <http://example.org/ies-rag-demo/>

SELECT DISTINCT ?person ?label WHERE {
    ?state ies:isStateOf ?person ; demo:roleIn demo:acmeBristol .
    ?person rdfs:label ?label .
}
```

**Result:** Alice Patel, Cara Lindqvist, Dan Okonkwo.

---

## Q5 — "What role was Alice holding when the London restructuring was announced?"

**Claude:** Intersect the event's date with Alice's role-states' periods.

```sparql
PREFIX ies:  <http://ies.data.gov.uk/ontology/ies4#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX demo: <http://example.org/ies-rag-demo/>

SELECT ?stateLabel ?eventDate ?statePeriod WHERE {
    demo:londonRestructuringNov2023 ies:inPeriod/ies:periodRepresentation ?eventDate .
    ?state ies:isStateOf demo:alice ;
           rdfs:label ?stateLabel ;
           ies:inPeriod/ies:periodRepresentation ?statePeriod .
    FILTER(STRSTARTS(?statePeriod, "2023-10"))
}
```

**Result:** Alice as London operations director, event 2023-11-22, state period 2023-10-01/...

**Claude (to user):** Alice was the London operations director at the time of the restructuring announcement (2023-11-22). She had transitioned into that role on 2023-10-01, the day after her Bristol manager role ended.

---

## Q6 — "Which organisations are based in Bristol?"

**Claude:** This is the dataset's weakest question because the toy data doesn't directly model org → location. I derive via event participation.

```sparql
PREFIX ies:  <http://ies.data.gov.uk/ontology/ies4#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX demo: <http://example.org/ies-rag-demo/>

SELECT DISTINCT ?org ?label WHERE {
    ?org a ies:Organisation ; rdfs:label ?label .
    ?state ies:isStateOf ?p ; demo:roleIn ?org .
    demo:bristolFireDrillMar2024 ies:isParticipantIn ?p ; ies:inLocation demo:bristol .
}
```

**Result:** Acme Logistics Bristol.

**Claude (to user):** Acme Logistics Bristol — derived from the Bristol-located fire drill event having participants who hold roles at that organisation. Caveat: the dataset doesn't model org → location directly, so a production IES4 dataset with explicit `ies:inLocation` on organisations would make this question one SPARQL hop rather than three.

---

## Pattern recap

Across six questions:

- 4D states made temporal questions deterministic (Q1, Q3, Q5)
- Explicit participant edges made participation questions exact (Q2)
- Set operations over states made cross-time queries (Q4) straightforward
- Compositional joins handled event/state intersection (Q5)

Flat document RAG would handle Q6 (atemporal, locational) but degrade on Q1/Q2/Q3/Q4/Q5 in proportion to how much the answer depends on dates and identity-stable references.

The MCP server's role: provide `onto_query` so the LLM can express the structural questions precisely, plus `onto_load` / `onto_marketplace_install` for the corpus setup. The intelligence — composing the right SPARQL, framing the answer in natural language — stays in the conversation.
