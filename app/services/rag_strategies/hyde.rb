module RagStrategies
  # HyDE (Hypothetical Document Embeddings). Ask a small LLM to write a
  # confident hypothetical answer first; embed THAT and search. Rationale:
  # the rulebook is written like answers, not questions, so the hypothetical
  # answer's embedding lands closer to actual rule text than the question's.
  class Hyde < Base
    def call
      hyde_text, cost = hypothesize
      qv = OpenaiEmbed.embed(input: hyde_text)

      chunks = StructuredRuleChunk
        .nearest_neighbors(:embedding, qv, distance: :cosine)
        .limit(TOP_K)
        .to_a

      RetrievalResult.new(
        chunks: chunks.map { |c| normalize(c) },
        aux_cost_cents: cost,
        aux_description: "HyDE rewrite via Haiku"
      )
    end

    private

    def hypothesize
      resp = AnthropicClient.client.messages.create(
        model: AnthropicClient::HAIKU_MODEL,
        max_tokens: 180,
        system: "You are a hockey rules expert generating a SHORT confident-sounding hypothetical answer used only for retrieval. Don't hedge, don't say you're unsure. 2-3 sentences.",
        messages: [ { role: "user", content: "Hypothesize an answer to: #{@question}" } ]
      )
      text = resp.content.first.text
      cost = AnthropicClient.estimate_haiku_cost_cents(
        input_tokens: resp.usage.input_tokens,
        output_tokens: resp.usage.output_tokens
      )
      [ text, cost ]
    end
  end
end
