class CompareRetrievalTask
  # Usage from console / runner:
  #   CompareRetrievalTask.call("How long is a minor penalty?")
  #   CompareRetrievalTask.call("What does Rule 22.1 say?", k: 5)
  def self.call(question, k: 3)
    query_vector = OpenaiEmbed.embed(input: question)

    naive = RuleChunk
      .nearest_neighbors(:embedding, query_vector, distance: :cosine)
      .limit(k)
      .to_a
    structured = StructuredRuleChunk
      .nearest_neighbors(:embedding, query_vector, distance: :cosine)
      .limit(k)
      .to_a

    puts ""
    puts "Q: #{question}"
    puts "-" * 80
    puts ""
    puts "NAIVE chunks (500-char windows, n=#{RuleChunk.count}):"
    naive.each_with_index { |c, i| print_chunk(i, c, c.rule_reference, c.content) }
    puts ""
    puts "STRUCTURED chunks (split on H2/H3, n=#{StructuredRuleChunk.count}):"
    structured.each_with_index { |c, i| print_chunk(i, c, c.rule_reference, c.content, c.title) }
    puts ""
    { naive: naive, structured: structured }
  end

  def self.print_chunk(i, chunk, rule_ref, content, title = nil)
    sim = (1 - chunk.neighbor_distance.to_f).round(3)
    label = title || (rule_ref.presence || "chunk #{chunk.chunk_index}")
    preview = content.gsub(/\s+/, " ").strip[0, 140]
    puts "  #{i + 1}. [sim=#{sim}] #{label}"
    puts "     #{preview}#{content.length > 140 ? "…" : ""}"
  end
end
