module RagStrategies
  # Structure-aware chunks re-embedded with text-embedding-3-large (3072 dims
  # vs 1536 for -small). Same retrieval mechanism (cosine), just a more
  # discriminating embedding model.
  class LargeEmbedding < Base
    MODEL = "text-embedding-3-large".freeze

    def call
      qv = OpenaiEmbed.embed(input: @question, model: MODEL)
      chunks = LargeRuleChunk
        .nearest_neighbors(:embedding, qv, distance: :cosine)
        .limit(TOP_K)
        .to_a
      RetrievalResult.new(chunks: chunks.map { |c| normalize(c) })
    end
  end
end
