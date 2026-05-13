class AddTsvectorToStructuredRuleChunks < ActiveRecord::Migration[8.1]
  def up
    # Generated column: Postgres keeps content_tsv in sync with title + content.
    # title is weighted A (more important), content B.
    execute <<~SQL
      ALTER TABLE structured_rule_chunks
        ADD COLUMN content_tsv tsvector
        GENERATED ALWAYS AS (
          setweight(to_tsvector('english', coalesce(title, '')),   'A') ||
          setweight(to_tsvector('english', coalesce(content, '')), 'B')
        ) STORED;
    SQL
    execute "CREATE INDEX index_structured_rule_chunks_on_content_tsv ON structured_rule_chunks USING GIN (content_tsv);"
  end

  def down
    execute "DROP INDEX IF EXISTS index_structured_rule_chunks_on_content_tsv;"
    execute "ALTER TABLE structured_rule_chunks DROP COLUMN IF EXISTS content_tsv;"
  end
end
