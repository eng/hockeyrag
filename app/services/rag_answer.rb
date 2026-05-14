class RagAnswer
  STRATEGIES = {
    "fixed"           => RagStrategies::FixedCosine,
    "structured"      => RagStrategies::StructuredCosine,
    "hybrid"          => RagStrategies::Hybrid,
    "rerank"          => RagStrategies::Rerank,
    "hyde"            => RagStrategies::Hyde,
    "large_embedding" => RagStrategies::LargeEmbedding,
    "hybrid_rerank"   => RagStrategies::HybridRerank
  }.freeze

  def self.call(question:, strategy: "fixed")
    klass = STRATEGIES.fetch(strategy) { raise ArgumentError, "Unknown RAG strategy: #{strategy.inspect}" }
    result = klass.new(question).call

    context = result.chunks.map { |c|
      label = c["title"].presence || c["rule_reference"].presence || "Chunk #{c["chunk_index"]}"
      "[#{label}]\n#{c["content"]}"
    }.join("\n\n---\n\n")

    AnswerCall.new(
      system: "You are a hockey rules expert. Answer using only the excerpts below. If they don't contain the answer, say so plainly.",
      user: "<excerpts>\n#{context}\n</excerpts>\n\nQuestion: #{question}",
      retrieved_chunks: result.chunks,
      aux_cost_cents: result.aux_cost_cents,
      aux_description: result.aux_description
    )
  end
end
