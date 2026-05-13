# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_13_235151) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "answers", force: :cascade do |t|
    t.decimal "aux_cost_cents", precision: 8, scale: 4, default: "0.0", null: false
    t.string "aux_description"
    t.text "content", default: "", null: false
    t.decimal "cost_cents", precision: 8, scale: 4
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.string "mode", null: false
    t.integer "output_tokens"
    t.bigint "question_id", null: false
    t.jsonb "retrieved_chunks", default: [], null: false
    t.string "status", default: "pending", null: false
    t.text "system_prompt"
    t.integer "total_ms"
    t.integer "ttft_ms"
    t.datetime "updated_at", null: false
    t.text "user_prompt"
    t.index ["question_id"], name: "index_answers_on_question_id"
  end

  create_table "large_rule_chunks", force: :cascade do |t|
    t.integer "chunk_index", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 3072
    t.string "rule_reference"
    t.string "section"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["rule_reference"], name: "index_large_rule_chunks_on_rule_reference"
  end

  create_table "questions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "rag_strategy", default: "fixed", null: false
    t.text "text", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rule_chunks", force: :cascade do |t|
    t.integer "chunk_index", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536
    t.string "rule_reference"
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_rule_chunks_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
  end

  create_table "structured_rule_chunks", force: :cascade do |t|
    t.integer "chunk_index", null: false
    t.text "content", null: false
    t.virtual "content_tsv", type: :tsvector, as: "(setweight(to_tsvector('english'::regconfig, (COALESCE(title, ''::character varying))::text), 'A'::\"char\") || setweight(to_tsvector('english'::regconfig, COALESCE(content, ''::text)), 'B'::\"char\"))", stored: true
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536
    t.string "rule_reference"
    t.string "section"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["content_tsv"], name: "index_structured_rule_chunks_on_content_tsv", using: :gin
    t.index ["embedding"], name: "index_structured_rule_chunks_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["rule_reference"], name: "index_structured_rule_chunks_on_rule_reference"
  end

  add_foreign_key "answers", "questions"
end
