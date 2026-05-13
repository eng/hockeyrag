class IngestLargeRulebookTask
  # Same structure-aware chunker as the structured library; only the embedding
  # model changes. This isolates the "bigger embedding model" variable for the
  # demo's side-by-side comparison.
  MODEL = "text-embedding-3-large".freeze  # 3072 dims, ~$0.13 / 1M tokens
  EMBED_BATCH_SIZE = 32

  def self.call
    chunks = IngestStructuredRulebookTask.build_chunks(File.read(IngestStructuredRulebookTask::RULEBOOK_PATH))
    puts "Re-embedding #{chunks.size} structured chunks with #{MODEL}…"

    LargeRuleChunk.delete_all

    chunks.each_slice(EMBED_BATCH_SIZE).with_index do |batch, batch_i|
      inputs = batch.map { |c| IngestStructuredRulebookTask.embed_input_for(c) }
      vectors = OpenaiEmbed.embed(input: inputs, model: MODEL)
      batch.each_with_index do |c, i|
        LargeRuleChunk.create!(
          chunk_index: batch_i * EMBED_BATCH_SIZE + i,
          section: c[:section],
          rule_reference: c[:rule_reference],
          title: c[:title],
          content: c[:content],
          embedding: vectors[i]
        )
      end
      print "."
      $stdout.flush
    end
    puts "\nDone. #{LargeRuleChunk.count} large-embedding chunks stored."
  end
end
