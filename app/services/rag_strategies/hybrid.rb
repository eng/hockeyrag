module RagStrategies
  # Combines cosine (semantic) and BM25 (keyword) search using Reciprocal Rank
  # Fusion. Picks up both "two-minute infraction" (semantic match for "minor
  # penalty") AND exact tokens like "Rule 16" that vector search misses.
  class Hybrid < Base
    RRF_K = 60
    CANDIDATES = 15

    def call
      ranked, score_for = rrf_with_scores(TOP_K)
      payload = ranked.map { |c| normalize(c, similarity: score_for[c.id].round(4)) }
      RetrievalResult.new(chunks: payload)
    end

    # Returns the top N chunks merged by RRF across cosine and BM25.
    # Used directly by #call and by composite strategies like HybridRerank.
    def rrf_top_chunks(n)
      ranked, _scores = rrf_with_scores(n)
      ranked
    end

    private

    def rrf_with_scores(n)
      cosine = cosine_top
      bm25   = bm25_top

      scores = Hash.new(0.0)
      cosine.each_with_index { |c, i| scores[c.id] += 1.0 / (RRF_K + i + 1) }
      bm25.each_with_index   { |c, i| scores[c.id] += 1.0 / (RRF_K + i + 1) }

      by_id = (cosine + bm25).uniq(&:id).index_by(&:id)
      top_ids = scores.sort_by { |_id, s| -s }.first(n).map(&:first)
      [ top_ids.map { |id| by_id[id] }, scores ]
    end

    def cosine_top
      qv = OpenaiEmbed.embed(input: @question)
      StructuredRuleChunk
        .nearest_neighbors(:embedding, qv, distance: :cosine)
        .limit(CANDIDATES)
        .to_a
    end

    # Build a tsquery from the question that:
    # - Requires numeric tokens (rule references like "22.1", measurements like "42")
    #   — they're rare and discriminating; missing them means the chunk almost
    #   certainly doesn't answer the question.
    # - ORs the non-numeric tokens — so common words like "rule" or "minor"
    #   don't have to all be present.
    #
    # plainto_tsquery alone uses pure AND, which knocks out the right chunk when
    # the question has filler ("What does Rule 22.1 SAY?" required "say" too).
    # Pure OR over-rewards common tokens (TOC stuffed with "rule" wins).
    def bm25_top
      query = build_tsquery
      return [] if query.blank?

      conn = StructuredRuleChunk.connection
      StructuredRuleChunk
        .where("content_tsv @@ to_tsquery('english', ?)", query)
        .order(Arel.sql(
          "ts_rank_cd(content_tsv, to_tsquery('english', #{conn.quote(query)})) DESC"
        ))
        .limit(CANDIDATES)
        .to_a
    rescue ActiveRecord::StatementInvalid
      # If the question produced an invalid tsquery (rare), fall back to nothing —
      # cosine alone will still drive RRF.
      []
    end

    STOPWORDS = %w[
      the a an of to in on at by for and or but is are was were be been being
      what when where why how which who whom does do did say said tell
      a an i me my you your he she it we us them
    ].to_set

    def build_tsquery
      tokens = @question
        .downcase
        .gsub(/[^\w\s.]/i, " ")
        .split(/\s+/)
        .reject { |t| t.length < 2 || STOPWORDS.include?(t) }
        .uniq

      return nil if tokens.empty?

      rare, common = tokens.partition { |t| t.match?(/\d/) }
      escaped = ->(t) { "'#{t.gsub("'", "''")}'" }

      if rare.any? && common.any?
        rare.map(&escaped).join(" & ") + " & (" + common.map(&escaped).join(" | ") + ")"
      else
        tokens.map(&escaped).join(" | ")
      end
    end
  end
end
