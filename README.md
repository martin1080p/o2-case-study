# O2 stores – RAG prototype

Question answering over the [O2 store export](https://www.o2.cz/servis/prodejny-export/export.json) with **Gemini**
(`gemini-embedding-001` + `gemini-2.5-flash`). Walkthrough with results: [`demo.ipynb`](demo.ipynb).

```
export.json ──► 1 chunk per store ──► embeddings (+ BM25 tokens) ──► data/index.json
question ──► hybrid search (BM25 + embeddings, RRF) ──► top 4 chunks ──► LLM ──► answer + store link (added by code, one store only)
```

- **Chunking** – one store = one chunk (name, address, phone, e-mail, weekly hours, holiday exceptions, URL).
  `CHUNK_FORMAT=compact` (default) groups days with the same hours, drops the address duplicated in the name and the
  URL (links are attached by code, `store_links`): fewer tokens per store than `CHUNK_FORMAT=full` (see the notebook).
- **Retrieval** – BM25 over 4-letter stems without diacritics catches exact names in any Czech form (“Zlicin” = “Zličíně”); multilingual embeddings
  handle English/Czech questions over Czech data. Only top-4 stores go into the prompt (under 1k prompt tokens instead of ~27k for all stores),
  plus all stores of a city the question names (*„prodejny v Brně“*, any Czech form).
- **No hallucinations** – the prompt requires the answer to come from the context and the store to match
  (name, street, city). If it is not among the retrieved stores, the model answers `NO_MATCH` and the question is asked
  again with more stores (`k = TOP_K + FALLBACK_STEP × attempt`: 4 → 24 → 44) – only the last attempt may state as a fact
  that no such O2 store exists (retrieval may miss a real store). Tested in `evaluate.py` with non-existent stores
  (incl. the Sušice store from the assignment, which is not in the current export).
  A **grounding check** in code (`check_grounding`) replaces any answer whose phone number or e-mail is not in
  the store records the LLM was given.
- **Guardrails** – the assistant answers only about O2 stores; other topics (code, general knowledge, tariffs) and
  attempts to override the rules or extract the prompt are refused – also tested in `evaluate.py`.
  Two layers: a keyword/length filter before and after the LLM (`check_input` / `check_output` – blocked messages
  cost no tokens) and the rules in the system prompt.
- **OpenAI-compatible API** – Gemini is called via the `openai` SDK, so Azure OpenAI is only a different
  `base_url`, key and model names.

## Run

API key: `cp .env.example .env` and fill in `GEMINI_API_KEY` (`.env` is gitignored).

**Notebook in Docker**

```bash
docker compose up -d --build
# open http://127.0.0.1:8889 (no token - bound to localhost only)
```

**Scripts locally**

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python rag.py ingest
.venv/bin/python rag.py ask "What is the phone number of the O2 store in OC Metropole Zličín?"
```

`python rag.py` without arguments starts an interactive chat. Models can be overridden with `CHAT_MODEL` / `EMBED_MODEL`.

## Evaluation

```bash
.venv/bin/python evaluate.py      # retrieval hit@1/hit@4 for bm25 vs embed vs hybrid + end-to-end answers
```

Questions are generated from the data (phone number of every store, EN/CZ alternately), so ground truth is known.

Results (2026-11-04, 139 stores):

| | hit@1 | hit@4 |
|---|---|---|
| BM25 | 100 % | 100 % |
| Embeddings | 100 % | 100 % |
| Hybrid | 100 % | 100 % |

Declined Czech store names (*na Zličíně*, *v Letňanech*, *v Palladiu*): **7/7** found by hybrid search.

End-to-end: **15/15** (10 phone numbers with the right link + 2 non-existent stores + 3 off-topic messages refused).

## Daily refresh

Stores open/close and `openingHoursRaw` holds the next 7 days, so re-ingest daily (logs added/removed stores,
swaps the index atomically):

```cron
0 5 * * * cd /path/to/o2-case-study && .venv/bin/python rag.py ingest >> data/ingest.log 2>&1
```
