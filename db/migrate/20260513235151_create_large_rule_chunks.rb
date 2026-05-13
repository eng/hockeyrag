class CreateLargeRuleChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :large_rule_chunks do |t|
      t.integer :chunk_index, null: false
      t.string  :section
      t.string  :rule_reference
      t.string  :title
      t.text    :content, null: false
      t.column  :embedding, "vector(3072)"  # text-embedding-3-large
      t.timestamps
    end
    # NOTE: pgvector's HNSW index has a 2000-dimension limit on the cosine ops
    # class. For 3072-dim vectors we fall back to a sequential scan, which is
    # fine for the demo's 223 rows but worth flagging if this ever scales.
    add_index :large_rule_chunks, :rule_reference
  end
end
