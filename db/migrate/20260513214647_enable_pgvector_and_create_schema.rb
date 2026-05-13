class EnablePgvectorAndCreateSchema < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector"

    create_table :rule_chunks do |t|
      t.integer :chunk_index, null: false
      t.text    :content,     null: false
      t.column  :embedding, "vector(1536)"
      t.string  :rule_reference
      t.timestamps
    end
    add_index :rule_chunks, :embedding,
      using: :hnsw, opclass: :vector_cosine_ops

    create_table :questions do |t|
      t.text :text, null: false
      t.timestamps
    end

    create_table :answers do |t|
      t.references :question, null: false, foreign_key: true
      t.string  :mode,            null: false
      t.text    :system_prompt
      t.text    :user_prompt
      t.text    :content, default: "", null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :ttft_ms
      t.integer :total_ms
      t.decimal :cost_cents, precision: 8, scale: 4
      t.jsonb   :retrieved_chunks, default: [], null: false
      t.string  :status, default: "pending", null: false
      t.timestamps
    end
  end
end
