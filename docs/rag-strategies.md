# Six RAG strategies — ELI5

Six radio buttons live under the question textarea. Each one is a different way to retrieve "the right chunks" before sending them to Claude. They all share the same final step (send retrieved chunks to Sonnet, get the answer), and they all share the same chunk-aware semantic goal — but they differ in *how* they decide which chunks count as "relevant."

Throughout, the "chunk library" is the on-disk collection of pre-embedded rulebook excerpts that the strategy searches over. The "query" is what we embed and search with. Different strategies vary the library, the query, or the search method.

---

## 1. Fixed-length chunks (baseline)

**What it does.** Take the entire rulebook (~260KB of markdown). Chop it into 500-character windows with 100 chars of overlap. Ignore meaning entirely — `Rule 16 — Minor Penalties\n\n- **16.1 ...` might get cut in the middle of a sentence. Embed each window. To answer a question, embed the question, find the 3 windows whose embeddings point in the most similar direction, send those to the model.

**Why it works at all.** Embeddings are powerful enough that "minor penalty two minutes" and the question "How long is a minor penalty?" land in nearby directions even when the chunk boundaries are awkward.

**Why it fails.** Chunks have no anchor — the "Rule 16" header often lives in a *different* chunk than its body. The embedding doesn't see "this paragraph is about Rule 16." For our test question, this strategy retrieved Rule 26 (delayed-penalty rule), an unrelated penalty-clock chunk, and Rule 9 (uniforms!). None of them stated "two minutes."

**Cost.** Just the Sonnet output. ~¢0.30/question.

---

## 2. Structure-aware chunks

**What it does.** Same idea, but instead of chopping every 500 characters, we chop on the markdown's natural seams — every `### Rule N — Title` becomes one chunk. Each chunk gets its section + rule title *prepended* to its content before embedding, so the vector encodes "this passage is about Rule 16 — Minor Penalties" rather than just "any player other than a goalkeeper is ruled off the ice for two minutes."

**Why it helps.** Embeddings now align by topic, not by accidental character window. A question about minor penalties retrieves chunks whose title literally says "Rule 16 — Minor Penalties," because that text was part of what got embedded.

**Why it fails.** Sometimes the *specific detail* you need (a number, a metric measurement, a dollar fine) gets diluted by the rest of the rule it lives in. Our "How big is the goal crease in metric units?" test case actually does **worse** with structured chunks for this reason — the specific measurement is one bullet among many in Rule 1, and the broader "Rule 1 — Rink" theme isn't what discriminates.

**Cost.** Same as fixed; embedding cost depends on text length, not chunk count, and the total characters embedded is identical. ~¢0.30/question.

---

## 3. Hybrid search (BM25 + cosine)

**What it does.** Cosine similarity is great at semantic match: "two-minute infraction" ≈ "minor penalty." BM25 (the classic keyword-search algorithm; Postgres has it built in as `tsvector`) is the opposite — terrible at synonyms, *excellent* at exact tokens like "Rule 22.1" or "two minutes" or "42 inches." Hybrid runs both, gets the top 15 from each, then merges them using **Reciprocal Rank Fusion**:

> A chunk's hybrid score = `1/(60 + cosine_rank) + 1/(60 + bm25_rank)`. A chunk that ranks #1 in *either* gets a big boost, regardless of how it did in the other.

The top 3 by combined score win.

**Why it helps.** Most questions are mixed — they want a meaning match *and* a token match. "What does Rule 22.1 say?" is hopeless for pure cosine (no rule number embeds usefully) but easy for BM25 (literally look up the string "22.1"). "What's a minor penalty?" is the opposite. Hybrid handles both.

**Why it fails.** Questions with neither strong semantic structure nor exact keywords (e.g., "Tell me something interesting about overtime") don't get much from either ranker.

**Cost.** Same as structured. BM25 lookup is a Postgres GIN index hit — free. ~¢0.30/question.

---

## 4. Retrieve-then-rerank

**What it does.** Pull the top 15 chunks by cosine (instead of just 3). Then send those 15 chunks to a small fast LLM (Claude Haiku) along with the original question, and ask it: "which 3 of these actually answer the question, in order?" Take Haiku's picks and send those 3 to Sonnet.

**Why it helps.** Vector math doesn't reason. It can tell that "minor penalty" and "two-minute infraction" are similar but can't notice that a high-similarity chunk is *about* minor penalties only as a side reference to delayed-penalty mechanics. Haiku reads the chunks like a human would and *judges* relevance to the specific question. It's the single highest-leverage improvement most production RAG systems make.

**Why it fails.** Haiku is fast but not free — it adds ~1-2 seconds of latency and a few cents per query. Also, if your top-15 doesn't contain the right chunk in the first place (because cosine missed it entirely), reranking can't help.

**Cost.** Sonnet (~¢0.30) + Haiku rerank call (~¢0.20). ~¢0.50/question.

---

## 5. HyDE — Hypothetical Document Embeddings

**What it does.** Counterintuitive trick. Before searching, ask Haiku: *"Write a confident hypothetical answer to this question, even though you don't actually know."* Then embed *that answer* and search with it instead of the question.

**Why it helps.** The rulebook is written like *answers*, not *questions*. The question "How long is a minor penalty?" embeds far from "A minor penalty is two minutes and the player is removed from the ice." The hypothetical answer "A minor penalty in NHL hockey lasts two minutes and the player serves it in the penalty box" embeds *very* close to the actual rule text. You're meeting the corpus where it lives. On the minor-penalty question, this jumps the top-result similarity from 0.60 to **0.76**.

**Why it fails.** If Haiku's hypothesis is wildly wrong, you'll embed-search toward the wrong neighborhood. Works best on questions Haiku can plausibly guess at, even badly. Less effective on questions with one specific obscure answer Haiku has no priors for.

**Cost.** Sonnet (~¢0.30) + small Haiku rewrite (~¢0.04). ~¢0.34/question.

---

## 6. Larger embedding model

**What it does.** Same structure-aware chunks, same cosine retrieval, same everything — but re-embedded with OpenAI's `text-embedding-3-large` (3072 dimensions) instead of `text-embedding-3-small` (1536 dimensions). The bigger model is trained on more data with more compute and represents finer semantic distinctions.

**Why it helps.** "Icing" the hockey infraction lives in a slightly different direction than "icing" the cake. "Boarding" the penalty is distinguishable from "boarding" the plane. Smaller models smear these together; larger models keep them apart. On our test question, this strategy puts Rule 16 first by a clearer margin than the smaller model does.

**Why it fails.** Doesn't help if your problem is bad chunking, query/corpus mismatch, or missing keyword matches. You're just shifting embeddings in the same vector space — better discrimination but not a different kind of search.

**Cost.** 3-large is ~6.5× more expensive per embed call than 3-small. For our 223-chunk ingestion: ~$0.013 vs ~$0.002. Per-query is identical (still one embed call). ~¢0.30/question (the cost difference is at ingestion time).

---

## 7. Hybrid + Rerank (the composite, recommended for this domain)

**What it does.** Stacks two of the techniques above. Hybrid (BM25 + cosine via RRF) pulls a candidate pool of 15 chunks. Then Claude Haiku reads all 15 and picks the best 3, just like the plain Rerank strategy. Result: the candidate pool is much smarter (catches keyword hits cosine missed AND semantic hits BM25 missed), and the final selection is much smarter (a small LLM judging real relevance, not just vector distance).

**Why it's the right call for a rulebook.** Hockey rulebook questions split into two shapes:
- **Conceptual:** "How long is a minor penalty?" — pure cosine handles these because the question's meaning aligns with rule body text.
- **Citation-heavy:** "What does Rule 22.1 say?" — pure cosine fails because rule numbers don't embed usefully. BM25 nails them.

A single strategy can't win both shapes. Hybrid+Rerank does: BM25 makes sure rule-number questions surface the right chunk in the candidate pool, then Haiku ensures conceptual questions get the actually-relevant chunk in the final 3 rather than a near-miss neighbor. On "What does Rule 22.1 say?" this strategy is the *only* one out of seven that retrieves Rule 22's actual content (everything else returns summary tables).

**Implementation note.** Our BM25 query builds a tsquery that requires numeric tokens (like "22.1" or "42") and ORs the non-numeric words. This is important — naive BM25 with `plainto_tsquery` ANDs everything, so filler words like "say" in "What does Rule 22.1 *say*?" knock out the right chunk. Numeric-tokens-required + word-tokens-optional is a small heuristic that handles this without overfitting.

**Why it fails.** Marginally for any question. The main failure mode is the same as plain Rerank: Haiku occasionally picks a chunk that *looks* relevant in its first 350 characters but trails off, missing the actual answer. Fixable by sending Haiku more characters per chunk (more cost) or by retrieving more candidates (more cost).

**Cost.** Same as Rerank, since BM25 is a free Postgres index lookup. ~¢0.50/question.

---

## A rough mental hierarchy

Roughly increasing complexity and effectiveness:

```
fixed  <  structured  <  hybrid  ≈  large_embedding  <  rerank  ≈  hyde  <  hybrid_rerank
```

In practice production systems stack several techniques. **Hybrid + Rerank is the standard recipe** for keyword-anchored domains like rulebooks, legal documents, API references, and policy manuals — anywhere users mix "tell me about X" questions with "what does section X.Y say" questions. The demo lets you try each technique in isolation to develop intuition for which lever moves the needle on which question, then graduate to the composite once you've internalized why each piece is there.
