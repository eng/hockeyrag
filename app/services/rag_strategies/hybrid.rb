module RagStrategies
  # Combines cosine (semantic) and BM25 (keyword) search using Reciprocal Rank
  # Fusion. Picks up both "two-minute infraction" (semantic match for "minor
  # penalty") AND exact tokens like "Rule 16" that vector search misses.
  class Hybrid < Base
    RRF_K = 60
    CANDIDATES = 15

    def call
      cosine = cosine_top
      bm25   = bm25_top

      scores = Hash.new(0.0)
      cosine.each_with_index { |c, i| scores[c.id] += 1.0 / (RRF_K + i + 1) }
      bm25.each_with_index   { |c, i| scores[c.id] += 1.0 / (RRF_K + i + 1) }

      by_id = (cosine + bm25).uniq(&:id).index_by(&:id)
      top_ids = scores.sort_by { |_id, s| -s }.first(TOP_K).map(&:first)

      payload = top_ids.map do |id|
        chunk = by_id[id]
        normalize(chunk, similarity: scores[id].round(4))
      end

      RetrievalResult.new(chunks: payload)
    end

    private

    def cosine_top
      qv = OpenaiEmbed.embed(input: @question)
      StructuredRuleChunk
        .nearest_neighbors(:embedding, qv, distance: :cosine)
        .limit(CANDIDATES)
        .to_a
    end

    def bm25_top
      StructuredRuleChunk
        .where("content_tsv @@ plainto_tsquery('english', ?)", @question)
        .order(Arel.sql(
          "ts_rank_cd(content_tsv, plainto_tsquery('english', #{StructuredRuleChunk.connection.quote(@question)})) DESC"
        ))
        .limit(CANDIDATES)
        .to_a
    end
  end
end
