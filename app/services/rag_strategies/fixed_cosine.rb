module RagStrategies
  # Original 500-char windows. Cosine similarity against the question embedding.
  class FixedCosine < Base
    def call
      qv = OpenaiEmbed.embed(input: @question)
      chunks = RuleChunk
        .nearest_neighbors(:embedding, qv, distance: :cosine)
        .limit(TOP_K)
        .to_a
      RetrievalResult.new(chunks: chunks.map { |c| normalize(c) })
    end
  end
end
