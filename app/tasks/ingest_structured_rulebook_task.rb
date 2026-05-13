class IngestStructuredRulebookTask
  RULEBOOK_PATH = Rails.root.join("db/seeds/NHL_Rules_2024-25.md")
  MAX_CHUNK_CHARS = 2000     # Split larger sections at sub-rule boundaries
  EMBED_BATCH_SIZE = 64

  H2_RE = /\A##\s+(.+?)\s*\z/
  H3_RE = /\A###\s+(.+?)\s*\z/
  RULE_REF_RE = /\bRule\s+\d+(?:\.\d+)?/i
  SUB_RULE_RE = /\A-\s+\*\*\d+\.\d+\b/   # e.g., "- **16.1 Minor Penalty.**"

  def self.call
    chunks = build_chunks(File.read(RULEBOOK_PATH))
    puts "Built #{chunks.size} structured chunks. Embedding in batches of #{EMBED_BATCH_SIZE}…"

    StructuredRuleChunk.delete_all

    chunks.each_slice(EMBED_BATCH_SIZE).with_index do |batch, batch_i|
      inputs = batch.map { |c| embed_input_for(c) }
      vectors = OpenaiEmbed.embed(input: inputs)
      batch.each_with_index do |c, i|
        StructuredRuleChunk.create!(
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
    puts "\nDone. #{StructuredRuleChunk.count} structured chunks stored."
  end

  # Builds an array of chunk hashes: { section:, title:, rule_reference:, content: }.
  # Splits the document at H2 (section) and H3 (rule) boundaries; further splits any
  # section longer than MAX_CHUNK_CHARS at sub-rule bullet boundaries.
  def self.build_chunks(text)
    sections = []
    current_section = nil
    current_title   = nil
    current_body    = []

    flush = ->(out) {
      next if current_body.empty? || current_title.nil?
      body = current_body.join("\n").strip
      next if body.empty?
      split_body(body).each do |piece|
        out << {
          section: current_section,
          title: current_title,
          rule_reference: current_title[RULE_REF_RE],
          content: piece
        }
      end
      current_body = []
    }

    text.each_line do |line|
      stripped = line.chomp
      if (m = stripped.match(H2_RE))
        flush.call(sections)
        current_section = m[1]
        current_title = m[1]   # used as title until an H3 overrides it
      elsif (m = stripped.match(H3_RE))
        flush.call(sections)
        current_title = m[1]
      else
        current_body << stripped
      end
    end
    flush.call(sections)

    sections
  end

  # Splits a single section body into <= MAX_CHUNK_CHARS pieces by walking forward
  # and starting a new chunk at each sub-rule bullet (- **N.M …**) once we exceed
  # the budget. Falls back to a hard char split for paragraphs without sub-rules.
  def self.split_body(body)
    return [ body ] if body.length <= MAX_CHUNK_CHARS

    pieces = []
    buf = []
    body.each_line do |line|
      if !buf.empty? && line.match?(SUB_RULE_RE) && buf.join.length >= MAX_CHUNK_CHARS / 2
        pieces << buf.join.strip
        buf = []
      end
      buf << line
    end
    pieces << buf.join.strip unless buf.empty?

    # Any single piece still oversized → hard split.
    pieces.flat_map { |p| p.length > MAX_CHUNK_CHARS ? hard_split(p) : p }
  end

  def self.hard_split(text, size: MAX_CHUNK_CHARS)
    text.scan(/.{1,#{size}}/m)
  end

  # The string we actually send to the embedding model. Prepending title+section
  # is the whole point of "structure-aware" — it lets the embedding see the rule
  # label and section context that the raw paragraph body might not contain.
  def self.embed_input_for(chunk)
    header = [ chunk[:section], chunk[:title] ].compact.uniq.join(" / ")
    "#{header}\n\n#{chunk[:content]}"
  end
end
