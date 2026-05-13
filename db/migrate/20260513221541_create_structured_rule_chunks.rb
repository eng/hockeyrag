class CreateStructuredRuleChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :structured_rule_chunks do |t|
      t.integer :chunk_index, null: false
      t.string  :section
      t.string  :rule_reference
      t.string  :title
      t.text    :content, null: false
      t.column  :embedding, "vector(1536)"
      t.timestamps
    end
    add_index :structured_rule_chunks, :embedding,
      using: :hnsw, opclass: :vector_cosine_ops
    add_index :structured_rule_chunks, :rule_reference
  end
end
