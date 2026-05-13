class RagAnswer
  TOP_K = 3

  STRATEGY_MODELS = {
    "fixed"      => RuleChunk,
    "structured" => StructuredRuleChunk
  }.freeze

  def self.call(question:, strategy: "fixed")
    model = STRATEGY_MODELS.fetch(strategy)
    query_vector = OpenaiEmbed.embed(input: question)

    chunks = model
      .nearest_neighbors(:embedding, query_vector, distance: :cosine)
      .limit(TOP_K)
      .to_a

    context = chunks.map { |c|
      label = chunk_label(c)
      "[#{label}]\n#{c.content}"
    }.join("\n\n---\n\n")

    AnswerCall.new(
      system: "You are a hockey rules expert. Answer using only the excerpts below. If they don't contain the answer, say so plainly.",
      user: "<excerpts>\n#{context}\n</excerpts>\n\nQuestion: #{question}",
      retrieved_chunks: chunks.map { |c|
        {
          "chunk_index" => c.chunk_index,
          "rule_reference" => c.rule_reference,
          "title" => (c.respond_to?(:title) ? c.title : nil),
          "content" => c.content,
          "similarity" => (1.0 - c.neighbor_distance.to_f).round(4)
        }
      }
    )
  end

  def self.chunk_label(chunk)
    return chunk.title if chunk.respond_to?(:title) && chunk.title.present?
    chunk.rule_reference.presence || "Chunk #{chunk.chunk_index}"
  end
end
