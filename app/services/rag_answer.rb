class RagAnswer
  TOP_K = 3

  def self.call(question:)
    query_vector = OpenaiEmbed.embed(input: question)

    chunks = RuleChunk
      .nearest_neighbors(:embedding, query_vector, distance: :cosine)
      .limit(TOP_K)
      .to_a

    context = chunks.map { |c|
      label = c.rule_reference.presence || "Chunk #{c.chunk_index}"
      "[#{label}]\n#{c.content}"
    }.join("\n\n---\n\n")

    AnswerCall.new(
      system: "You are a hockey rules expert. Answer using only the excerpts below. If they don't contain the answer, say so plainly.",
      user: "<excerpts>\n#{context}\n</excerpts>\n\nQuestion: #{question}",
      retrieved_chunks: chunks.map { |c|
        {
          "chunk_index" => c.chunk_index,
          "rule_reference" => c.rule_reference,
          "content" => c.content,
          "similarity" => (1.0 - c.neighbor_distance.to_f).round(4)
        }
      }
    )
  end
end
