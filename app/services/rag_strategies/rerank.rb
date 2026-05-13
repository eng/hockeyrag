module RagStrategies
  # Retrieve 15 candidates by cosine, then ask Claude Haiku to pick the 3
  # most relevant. Haiku understands nuance that pure vector math can't —
  # e.g., that a chunk *mentions* minor penalties but is really about
  # delayed-penalty mechanics rather than the duration of a minor.
  class Rerank < Base
    CANDIDATES = 15

    def call
      qv = OpenaiEmbed.embed(input: @question)
      candidates = StructuredRuleChunk
        .nearest_neighbors(:embedding, qv, distance: :cosine)
        .limit(CANDIDATES)
        .to_a

      picks, cost = rerank_with_haiku(candidates)
      payload = picks.map { |c| normalize(c) }

      RetrievalResult.new(
        chunks: payload,
        aux_cost_cents: cost,
        aux_description: "Rerank via Haiku"
      )
    end

    private

    def rerank_with_haiku(candidates)
      menu = candidates.each_with_index.map { |c, i|
        "[#{i + 1}] #{c.title}\n#{c.content[0, 350]}"
      }.join("\n\n")

      prompt = <<~PROMPT
        You are choosing which excerpts best answer a hockey rules question.
        Return ONLY valid JSON of this shape: {"picks": [N, N, N]}, where each
        N is a candidate number from 1 to #{candidates.length}. Pick exactly
        the 3 most relevant in order of relevance.

        Question: #{@question}

        Candidates:
        #{menu}
      PROMPT

      resp = AnthropicClient.client.messages.create(
        model: AnthropicClient::HAIKU_MODEL,
        max_tokens: 200,
        system: "You are a precise retrieval reranker. Respond with valid JSON only.",
        messages: [ { role: "user", content: prompt } ]
      )

      text = resp.content.first.text
      json = text[/\{.*\}/m] || "{\"picks\":[1,2,3]}"
      indices = JSON.parse(json).fetch("picks", []).first(3)
      picks = indices.map { |i| candidates[i - 1] }.compact
      picks = candidates.first(3) if picks.empty?

      cost = AnthropicClient.estimate_haiku_cost_cents(
        input_tokens: resp.usage.input_tokens,
        output_tokens: resp.usage.output_tokens
      )

      [ picks, cost ]
    end
  end
end
