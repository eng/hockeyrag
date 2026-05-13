module RagStrategies
  # H2/H3 chunks with title prepended at ingest. Cosine search.
  class StructuredCosine < Base
    def call
      qv = OpenaiEmbed.embed(input: @question)
      chunks = StructuredRuleChunk
        .nearest_neighbors(:embedding, qv, distance: :cosine)
        .limit(TOP_K)
        .to_a
      RetrievalResult.new(chunks: chunks.map { |c| normalize(c) })
    end
  end
end
