module RagStrategies
  # All strategies return a RetrievalResult: an Array of context-chunk hashes
  # plus optional aux-call metadata (extra LLM call costs that should appear in
  # the answer's reported total).
  RetrievalResult = Struct.new(:chunks, :aux_cost_cents, :aux_description, keyword_init: true) do
    def initialize(chunks:, aux_cost_cents: 0.0, aux_description: nil)
      super
    end
  end

  class Base
    TOP_K = 3

    def initialize(question)
      @question = question
    end

    def call
      raise NotImplementedError
    end

    private

    def normalize(chunk, similarity: nil)
      sim = similarity || (chunk.respond_to?(:neighbor_distance) && chunk.neighbor_distance ? (1.0 - chunk.neighbor_distance.to_f).round(4) : nil)
      {
        "chunk_index" => chunk.chunk_index,
        "rule_reference" => chunk.rule_reference,
        "title" => (chunk.respond_to?(:title) ? chunk.title : nil),
        "content" => chunk.content,
        "similarity" => sim
      }
    end
  end
end
