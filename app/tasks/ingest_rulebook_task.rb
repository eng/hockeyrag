class IngestRulebookTask
  RULEBOOK_PATH = Rails.root.join("db/seeds/NHL_Rules_2024-25.md")
  CHUNK_SIZE = 500       # characters
  CHUNK_OVERLAP = 100
  EMBED_BATCH_SIZE = 64

  def self.call
    text = File.read(RULEBOOK_PATH)
    chunks = chunk(text)
    puts "Embedding #{chunks.size} chunks in batches of #{EMBED_BATCH_SIZE}…"

    RuleChunk.delete_all

    chunks.each_slice(EMBED_BATCH_SIZE).with_index do |batch, batch_i|
      vectors = OpenaiEmbed.embed(input: batch)
      batch.each_with_index do |chunk_text, i|
        RuleChunk.create!(
          chunk_index: batch_i * EMBED_BATCH_SIZE + i,
          content: chunk_text,
          embedding: vectors[i],
          rule_reference: extract_rule_ref(chunk_text)
        )
      end
      print "."
      $stdout.flush
    end
    puts "\nDone. #{RuleChunk.count} chunks stored."
  end

  def self.chunk(text)
    chunks = []
    pos = 0
    while pos < text.length
      chunks << text[pos, CHUNK_SIZE]
      pos += CHUNK_SIZE - CHUNK_OVERLAP
    end
    chunks
  end

  def self.extract_rule_ref(text)
    text.match(/Rule\s+\d+(\.\d+)?/i)&.to_s
  end
end
