"""
verifiabench — an un-game-able benchmark for scientific-workflow LLM reliability.

Existing science-LLM benchmarks grade the answer with string match or an LLM judge, so a
fluent-but-fabricated term can score as correct. verifiabench grades with a CLOSED-WORLD oracle:
every ontology term a model emits must EXIST in the authority (here the real Biolink Model) and
the output must satisfy the task's structural constraints. Correctness is set-membership plus
constraint satisfaction, not similarity, so fluency cannot buy a point.

Task: given a real gene-disease fact, write Biolink-typed RDF asserting it. The oracle extracts
every biolink term from the output and checks it against the Biolink Model's declared terms, then
checks the structure (a real Gene, a real Disease, a real association predicate). The headline is
the gap between RAW capability (the output looks like structured Biolink RDF) and VERIFIED
capability (its terms are real and the structure holds).

Deterministic oracle, no LLM judge. Model under test is queried over an OpenAI-compatible API.
"""
import json, os, re, sys, time
import requests
import rdflib
from rdflib import RDF

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA, RES = os.path.join(ROOT, "data"), os.path.join(ROOT, "results")
os.makedirs(RES, exist_ok=True)
API = os.environ.get("VB_API", "http://localhost:8080/v1/chat/completions")
BL = "https://w3id.org/biolink/vocab/"

with open(os.path.join(DATA, "biolink_vocab.json")) as f:
    DECLARED = set(json.load(f)["declared"])
GENE, DISEASE = BL + "Gene", BL + "Disease"
# real Biolink slots that legitimately relate a gene to a condition/disease
ASSOC_SLOTS = {BL + s for s in ("gene_associated_with_condition", "associated_with",
               "related_to", "contributes_to", "causes", "biomarker_for")} & DECLARED

# 30 real, well-established gene-disease facts
FACTS = [
    ("BRAF", "cardiofaciocutaneous syndrome"), ("TP53", "Li-Fraumeni syndrome"),
    ("PTEN", "Cowden syndrome"), ("EGFR", "non-small cell lung carcinoma"),
    ("BRCA1", "breast cancer"), ("BRCA2", "breast cancer"), ("KRAS", "pancreatic carcinoma"),
    ("APC", "familial adenomatous polyposis"), ("RB1", "retinoblastoma"), ("VHL", "von Hippel-Lindau disease"),
    ("CFTR", "cystic fibrosis"), ("HTT", "Huntington disease"), ("FMR1", "fragile X syndrome"),
    ("DMD", "Duchenne muscular dystrophy"), ("HBB", "beta thalassemia"), ("F8", "hemophilia A"),
    ("LDLR", "familial hypercholesterolemia"), ("MLH1", "Lynch syndrome"), ("NF1", "neurofibromatosis type 1"),
    ("SMN1", "spinal muscular atrophy"), ("PAH", "phenylketonuria"), ("G6PD", "G6PD deficiency"),
    ("ATM", "ataxia telangiectasia"), ("TSC1", "tuberous sclerosis"), ("MECP2", "Rett syndrome"),
    ("SCN1A", "Dravet syndrome"), ("COL1A1", "osteogenesis imperfecta"), ("GBA", "Gaucher disease"),
    ("HFE", "hereditary hemochromatosis"), ("PKD1", "polycystic kidney disease"),
]

PROMPT = ("Using the Biolink Model, write RDF in Turtle asserting that the gene {g} is associated "
          "with the disease {d}. Use only real Biolink Model classes and predicates with the "
          "`biolink:` prefix (biolink: = <{ns}>). Output only the Turtle.")

def query(model, prompt, timeout=120):
    r = requests.post(API, json={"model": model, "messages": [{"role": "user", "content": prompt}],
                                 "max_tokens": 400, "temperature": 0}, timeout=timeout)
    return r.json()["choices"][0]["message"]["content"]

def strip_fence(text):
    m = re.search(r"```(?:turtle|ttl)?\s*(.*?)```", text, re.S)
    return m.group(1) if m else text

def extract(output):
    """Return (biolink_terms:set, structure:dict, parsed:bool). Robust to whatever prefix a
    model maps to the Biolink namespace: parse the Turtle with rdflib (prefix-aware) and fall
    back to prefix-resolved regex if it does not parse."""
    text = strip_fence(output)
    terms = set()
    struct = {"gene": False, "disease": False, "assoc": False}
    try:
        g = rdflib.Graph().parse(data=text, format="turtle")
    except Exception:
        g = None
    if g is not None and len(g):
        for s, p, o in g:
            if str(p).startswith(BL): terms.add(str(p))
            if p == RDF.type and str(o).startswith(BL): terms.add(str(o))
        typed = {}
        for s, _, o in g.triples((None, RDF.type, None)):
            typed.setdefault(str(s), set()).add(str(o))
        struct["gene"] = any(GENE in ts for ts in typed.values())
        struct["disease"] = any(DISEASE in ts for ts in typed.values())
        struct["assoc"] = any(str(p) in ASSOC_SLOTS for _, p, _ in g)
        return terms, struct, True
    # fallback: find prefixes bound to the biolink namespace, then extract their CURIEs
    prefixes = set(re.findall(r"@prefix\s+(\w+):\s*<" + re.escape(BL) + r">", text))
    prefixes.add("biolink")
    for pre in prefixes:
        for m in re.findall(r"\b" + re.escape(pre) + r":([A-Za-z_]\w*)", text):
            terms.add(BL + m)
    for m in re.findall(re.escape(BL) + r"([A-Za-z_]\w*)", text):
        terms.add(BL + m)
    struct = {"gene": GENE in terms, "disease": DISEASE in terms, "assoc": len(terms & ASSOC_SLOTS) > 0}
    return terms, struct, False

def score(output):
    terms, struct, parsed = extract(output)
    real = {t for t in terms if t in DECLARED}
    fake = terms - real
    raw_ok = len(terms) > 0                        # produced biolink-namespace terms
    verified_ok = struct["gene"] and struct["disease"] and struct["assoc"] and len(fake) == 0
    return {
        "parsed_turtle": parsed, "n_terms": len(terms), "n_real": len(real), "n_fake": len(fake),
        "term_existence_rate": (len(real) / len(terms)) if terms else 0.0,
        "raw_ok": raw_ok, "verified_ok": verified_ok,
        "has_gene": struct["gene"], "has_disease": struct["disease"], "has_assoc": struct["assoc"],
        "fake_terms": sorted(t.split("/")[-1] for t in fake)[:6],
        "output": output[:600],
    }

def run_model(model):
    per = []
    for i, (g, d) in enumerate(FACTS):
        try:
            out = query(model, PROMPT.format(g=g, d=d, ns=BL))
        except Exception as e:
            out = f"__ERROR__ {e}"
        s = score(out); s["gene"] = g; s["disease"] = d
        per.append(s)
        print(f"  [{i+1}/{len(FACTS)}] {g}/{d[:22]:22s} raw={s['raw_ok']} verified={s['verified_ok']} "
              f"real={s['n_real']} fake={s['n_fake']}", flush=True)
    n = len(per)
    agg = {
        "model": model, "n_tasks": n,
        "raw_capability": round(sum(x["raw_ok"] for x in per) / n, 3),
        "verified_capability": round(sum(x["verified_ok"] for x in per) / n, 3),
        "mean_term_existence": round(sum(x["term_existence_rate"] for x in per) / n, 3),
        "tasks_with_any_fabricated_term": sum(x["n_fake"] > 0 for x in per),
        "total_fabricated_terms": sum(x["n_fake"] for x in per),
    }
    agg["verification_gap"] = round(agg["raw_capability"] - agg["verified_capability"], 3)
    return agg, per

def main():
    models = sys.argv[1:] or ["mlx-community/Qwen2.5-3B-Instruct-4bit"]
    board = []
    for m in models:
        print(f"[*] running {m} ...", flush=True)
        agg, per = run_model(m)
        board.append(agg)
        json.dump(per, open(os.path.join(RES, "per_task_" + m.split("/")[-1] + ".json"), "w"), indent=2)
        print("   ", json.dumps(agg), flush=True)
    board.sort(key=lambda a: a["verified_capability"], reverse=True)
    out = {"authority": "Biolink Model", "n_tasks": len(FACTS),
           "oracle": "closed-world term existence + structural constraints (deterministic, no LLM judge)",
           "leaderboard": board}
    json.dump(out, open(os.path.join(RES, "results.json"), "w"), indent=2)
    print(json.dumps(out, indent=2))

if __name__ == "__main__":
    main()
