module RagStrategies
  # The "production recipe" for keyword-heavy domains. Hybrid pulls candidates
  # that BOTH cosine and BM25 surface — so exact tokens like "Rule 22.1" don't
  # get lost — then Claude Haiku reranks to the final top 3 with semantic
  # judgment of relevance. Same cost profile as plain Rerank since BM25
  # lookup is free (Postgres GIN index).
  class HybridRerank < Base
    CANDIDATES = 15

    def call
      candidates = Hybrid.new(@question).rrf_top_chunks(CANDIDATES)
      picks, cost = Rerank.rerank_chunks(candidates, @question)
      payload = picks.map { |c| normalize(c) }

      RetrievalResult.new(
        chunks: payload,
        aux_cost_cents: cost,
        aux_description: "Rerank via Haiku (on hybrid candidates)"
      )
    end
  end
end
