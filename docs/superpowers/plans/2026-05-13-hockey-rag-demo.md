# Hockey RAG Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A 2-day Rails 8 demo that compares three answer modes — Naive (no KB), Brute Force (full rulebook in prompt), and RAG (pgvector retrieval) — side-by-side with live streaming and per-mode timing/token/cost metrics.

**Architecture:** Single Rails 8 app. Postgres + pgvector for embeddings (`neighbor` gem). Solid Queue for background ingestion + streaming generation jobs. Turbo Streams for live per-answer rendering. **OpenAI** for embeddings (`text-embedding-3-small`, 1536-dim), Anthropic for chat (`claude-sonnet-4-6`). Three thin service objects (`NaiveAnswer`, `BruteForceAnswer`, `RagAnswer`) that build an `AnswerCall` value object; one `GenerateAnswerJob` runs the streamed completion and broadcasts deltas. One controller (`QuestionsController`), one ERB view (`questions/show`), one partial (`answers/_meta`).

**Tech Stack:** Rails 8.1, Ruby 4.0, Postgres 14 + pgvector, `neighbor` gem, official `anthropic` Ruby SDK, OpenAI embeddings via thin Faraday client, `dotenv-rails` for env loading, Turbo Streams, raw CSS (see Task 12).

**Deviations from original spec:**
1. Ingestion task reads from `db/seeds/NHL_Rules_2024-25.md` (already on disk) instead of a PDF.
2. Embeddings come from OpenAI's `text-embedding-3-small` (1536-dim) instead of Voyage AI's `voyage-3` (1024-dim). User already has an OpenAI key.
3. API keys live in `.env` loaded by `dotenv-rails`.

**Testing posture:** This is a demo, not production. Each task ends with a concrete smoke check (rails console, curl, or browser). We are NOT writing a full RSpec/Minitest suite — the spec explicitly says "no error handling beyond happy path". The verification step in each task is the test.

---

## File Map

**Create:**
- `db/migrate/<ts>_enable_pgvector.rb`
- `db/migrate/<ts>_create_rule_chunks.rb`
- `db/migrate/<ts>_create_questions.rb`
- `db/migrate/<ts>_create_answers.rb`
- `db/migrate/<ts>_create_solid_queue_tables.rb` (only if `bin/rails db:prepare` doesn't auto-load schemas — Rails 8 default does)
- `app/models/rule_chunk.rb`
- `app/models/question.rb`
- `app/models/answer.rb`
- `app/lib/openai_embed.rb` — minimal OpenAI embedding HTTP client
- `app/lib/anthropic_client.rb` — thin wrapper that returns the official `Anthropic::Client` instance (or use SDK directly in the job)
- `app/services/answer_call.rb` — value object: `system_prompt`, `user_prompt`, `retrieved_chunks`
- `app/services/naive_answer.rb`
- `app/services/brute_force_answer.rb`
- `app/services/rag_answer.rb`
- `app/tasks/ingest_rulebook_task.rb` (autoloaded via `app/tasks` added to `config.autoload_paths`)
- `app/jobs/generate_answer_job.rb`
- `app/controllers/questions_controller.rb`
- `app/views/questions/show.html.erb`
- `app/views/answers/_meta.html.erb`
- `app/views/answers/_panel.html.erb` (renders one of the three panels)
- `app/assets/stylesheets/application.css` (or use Tailwind — see Task 12)
- `.env` — `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`
- `.gitignore` — add `.env`

**Modify:**
- `Gemfile` — add `neighbor`, `anthropic`, `faraday`
- `config/routes.rb` — add `resources :questions, only: %i[create show]` and `root "questions#show"` (with a default question or redirect to new)
- `config/application.rb` — `config.autoload_paths += %W[#{config.root}/app/tasks #{config.root}/app/services #{config.root}/app/lib]`
- `app/views/layouts/application.html.erb` — include Turbo + Tailwind/CSS

---

## Task 1: Bundle dependencies and prepare database

**Files:**
- Modify: `Gemfile`
- Run: `bundle install`
- Run: `bin/rails db:create`

- [ ] **Step 1: Add gems to Gemfile**

Add these three lines to `Gemfile` (after the existing `gem "image_processing"` line):

```ruby
gem "neighbor"
gem "anthropic"
gem "faraday"
gem "dotenv-rails", groups: %i[development test]
```

- [ ] **Step 2: Install**

```bash
bundle install
```

Expected: bundle resolves cleanly. If `anthropic` gem is unavailable on rubygems under that name, fall back to `gem "anthropic-sdk-ruby"` and adjust requires. (As of 2026-05, the official gem name is `anthropic`.)

- [ ] **Step 3: Create the database**

```bash
bin/rails db:create
```

Expected: `Created database 'hockeyrag_development'` and `Created database 'hockeyrag_test'`.

- [ ] **Step 4: Verify pgvector is installed**

```bash
psql hockeyrag_development -c "CREATE EXTENSION IF NOT EXISTS vector; SELECT extversion FROM pg_extension WHERE extname = 'vector';"
```

Expected: a single row with the pgvector version (e.g., `0.7.x`). If the `CREATE EXTENSION` fails with "extension 'vector' is not available", install pgvector first: `brew install pgvector` then restart Postgres (`brew services restart postgresql@14`). Drop the extension again before the migration runs (`psql hockeyrag_development -c "DROP EXTENSION vector;"`) so the migration installs it cleanly.

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "Add neighbor, anthropic, faraday gems for RAG demo"
```

---

## Task 2: Database schema — pgvector + three tables

**Files:**
- Create: `db/migrate/<ts>_enable_pgvector_and_create_schema.rb`

- [ ] **Step 1: Generate one combined migration**

```bash
bin/rails generate migration EnablePgvectorAndCreateSchema
```

- [ ] **Step 2: Write the migration**

Edit the generated file at `db/migrate/<ts>_enable_pgvector_and_create_schema.rb`:

```ruby
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
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected: all three tables created. `db/schema.rb` shows `enable_extension "vector"` and the three tables.

- [ ] **Step 4: Verify**

```bash
bin/rails runner 'puts ActiveRecord::Base.connection.tables.sort.inspect'
```

Expected output contains `["answers", "ar_internal_metadata", "questions", "rule_chunks", "schema_migrations"]` (Solid Queue tables get loaded into a separate DB in Rails 8 default config; that's fine).

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "Create rule_chunks, questions, answers schema with pgvector"
```

---

## Task 3: Models with associations and neighbor

**Files:**
- Create: `app/models/rule_chunk.rb`
- Create: `app/models/question.rb`
- Create: `app/models/answer.rb`
- Modify: `config/application.rb` (autoload paths)

- [ ] **Step 1: Add autoload paths**

In `config/application.rb`, inside the `class Application < Rails::Application` block, add:

```ruby
config.autoload_paths += %W[
  #{config.root}/app/tasks
  #{config.root}/app/services
  #{config.root}/app/lib
]
```

- [ ] **Step 2: Write `app/models/rule_chunk.rb`**

```ruby
class RuleChunk < ApplicationRecord
  has_neighbors :embedding, dimensions: 1536
end
```

- [ ] **Step 3: Write `app/models/question.rb`**

```ruby
class Question < ApplicationRecord
  has_many :answers, dependent: :destroy

  validates :text, presence: true
end
```

- [ ] **Step 4: Write `app/models/answer.rb`**

```ruby
class Answer < ApplicationRecord
  MODES = %w[naive brute_force rag].freeze

  belongs_to :question

  validates :mode, inclusion: { in: MODES }

  def display_name
    case mode
    when "naive"       then "Naive (no rulebook)"
    when "brute_force" then "Brute Force (full rulebook)"
    when "rag"         then "RAG (top-3 chunks)"
    end
  end
end
```

- [ ] **Step 5: Smoke-check in console**

```bash
bin/rails runner 'q = Question.create!(text: "test"); a = q.answers.create!(mode: "naive"); puts a.display_name; q.destroy!'
```

Expected: `Naive (no rulebook)` printed, no errors.

- [ ] **Step 6: Commit**

```bash
git add app/models config/application.rb
git commit -m "Add RuleChunk, Question, Answer models"
```

---

## Task 4: OpenAI embedding client + .env loading

**Files:**
- Create: `app/lib/openai_embed.rb`
- Create: `.env` (user provides the values)
- Modify: `.gitignore`

- [ ] **Step 1: Write the client**

`app/lib/openai_embed.rb`:

```ruby
require "faraday"
require "json"

module OpenaiEmbed
  ENDPOINT = "https://api.openai.com/v1/embeddings"
  MODEL = "text-embedding-3-small"  # 1536 dims, cheap (~$0.02/1M tokens)

  class Error < StandardError; end

  # Accepts a single String or an Array of Strings; returns a single vector or array of vectors accordingly.
  def self.embed(input:, model: MODEL)
    response = connection.post("") do |req|
      req.headers["Authorization"] = "Bearer #{api_key}"
      req.headers["Content-Type"] = "application/json"
      req.body = JSON.generate(model: model, input: Array(input))
    end

    raise Error, "OpenAI #{response.status}: #{response.body}" unless response.success?

    body = JSON.parse(response.body)
    vectors = body.fetch("data").sort_by { |d| d["index"] }.map { |d| d.fetch("embedding") }
    input.is_a?(Array) ? vectors : vectors.first
  end

  def self.connection
    @connection ||= Faraday.new(url: ENDPOINT) do |f|
      f.request :retry, max: 2, interval: 0.5
      f.adapter Faraday.default_adapter
      f.options.timeout = 60
    end
  end

  def self.api_key
    ENV.fetch("OPENAI_API_KEY")
  end
end
```

- [ ] **Step 2: Update `.gitignore` so `.env` doesn't get committed**

Append to `.gitignore`:

```
.env
.env.*
!.env.example
```

- [ ] **Step 3: Create `.env.example`**

`.env.example`:

```
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
```

(User creates their own `.env` from this template.)

- [ ] **Step 4: Smoke test**

```bash
bin/rails runner 'v = OpenaiEmbed.embed(input: "minor penalty"); puts v.length; puts v.first(3).inspect'
```

Expected: `1536` followed by an array of three floats.

- [ ] **Step 5: Commit**

```bash
git add app/lib/openai_embed.rb .gitignore .env.example
git commit -m "Add OpenAI embedding client and dotenv setup"
```

---

## Task 5: Anthropic client wrapper

**Files:**
- Create: `app/lib/anthropic_client.rb`

- [ ] **Step 1: Confirm the gem's interface**

```bash
bin/rails runner 'require "anthropic"; puts Anthropic::Client.name'
```

Expected: `Anthropic::Client`. (If the gem requires different requires/initialization, adjust the wrapper below accordingly. As of late 2025 the official SDK exposes `Anthropic::Client.new(api_key: ...)` with `.messages.stream`.)

- [ ] **Step 2: Write the wrapper**

`app/lib/anthropic_client.rb`:

```ruby
require "anthropic"

module AnthropicClient
  MODEL = "claude-sonnet-4-6"
  MAX_TOKENS = 800

  # Sonnet 4.6 pricing: $3 / 1M input tokens, $15 / 1M output tokens.
  INPUT_COST_PER_TOKEN_CENTS  = 300.0 / 1_000_000  # = 0.0003 cents/token
  OUTPUT_COST_PER_TOKEN_CENTS = 1500.0 / 1_000_000 # = 0.0015 cents/token

  def self.client
    @client ||= Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))
  end

  def self.estimate_cost_cents(input_tokens:, output_tokens:)
    cents = input_tokens.to_i * INPUT_COST_PER_TOKEN_CENTS +
            output_tokens.to_i * OUTPUT_COST_PER_TOKEN_CENTS
    cents.round(4)
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add app/lib/anthropic_client.rb
git commit -m "Add Anthropic client wrapper with cost estimation"
```

---

## Task 6: Rulebook ingestion task (reads markdown, not PDF)

**Files:**
- Create: `app/tasks/ingest_rulebook_task.rb`

This is the key deviation from the original spec.

- [ ] **Step 1: Write the task**

`app/tasks/ingest_rulebook_task.rb`:

```ruby
class IngestRulebookTask
  RULEBOOK_PATH = Rails.root.join("db/seeds/NHL_Rules_2024-25.md")
  CHUNK_SIZE = 500       # characters
  CHUNK_OVERLAP = 100
  EMBED_BATCH_SIZE = 64  # Voyage accepts batched inputs; cheaper than 1-by-1

  def self.call
    text = File.read(RULEBOOK_PATH)
    chunks = chunk(text)
    puts "Embedding #{chunks.size} chunks in batches of #{EMBED_BATCH_SIZE}…"

    RuleChunk.delete_all

    chunks.each_slice(EMBED_BATCH_SIZE).with_index do |batch, batch_i|
      vectors = OpenaiEmbed.embed(input: batch)
      RuleChunk.insert_all!(
        batch.each_with_index.map do |chunk_text, i|
          global_index = batch_i * EMBED_BATCH_SIZE + i
          {
            chunk_index: global_index,
            content: chunk_text,
            embedding: vectors[i],
            rule_reference: extract_rule_ref(chunk_text),
            created_at: Time.current,
            updated_at: Time.current
          }
        end
      )
      print "."
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
```

Note on `insert_all!` with `vector` columns: the `neighbor` gem expects assignment via the model getter/setter to use the pgvector adapter. If `insert_all!` fails to coerce arrays into the vector type, fall back to the simpler form:

```ruby
batch.each_with_index do |chunk_text, i|
  RuleChunk.create!(
    chunk_index: batch_i * EMBED_BATCH_SIZE + i,
    content: chunk_text,
    embedding: vectors[i],
    rule_reference: extract_rule_ref(chunk_text)
  )
end
```

Slower but reliable. Use the fallback if the first form errors.

- [ ] **Step 2: Run the ingestion (requires OPENAI_API_KEY in .env)**

```bash
bin/rails runner 'IngestRulebookTask.call'
```

Expected: stdout shows progress dots and ends with something like `Done. ~660 chunks stored.` (262,969 chars ÷ 400 step ≈ 657 chunks).

- [ ] **Step 3: Verify in console**

```bash
bin/rails runner 'c = RuleChunk.first; puts c.chunk_index; puts c.content.length; puts c.embedding.length; puts c.rule_reference.inspect'
```

Expected: `0`, around `500`, `1536`, and some `"Rule N"` or `nil`.

- [ ] **Step 4: Verify retrieval works end-to-end**

```bash
bin/rails runner '
  q = OpenaiEmbed.embed(input: "How long is a minor penalty?")
  top = RuleChunk.nearest_neighbors(:embedding, q, distance: :cosine).limit(3)
  top.each { |c| puts "[#{c.rule_reference || c.chunk_index}] #{c.neighbor_distance.round(3)} :: #{c.content[0,80]}" }
'
```

Expected: 3 chunks printed, distances under ~0.5, content mentioning minor penalties / two-minute durations.

- [ ] **Step 5: Commit**

```bash
git add app/tasks/ingest_rulebook_task.rb
git commit -m "Add IngestRulebookTask reading from NHL markdown seed"
```

---

## Task 7: The three answer services

**Files:**
- Create: `app/services/answer_call.rb`
- Create: `app/services/naive_answer.rb`
- Create: `app/services/brute_force_answer.rb`
- Create: `app/services/rag_answer.rb`

- [ ] **Step 1: AnswerCall value object**

`app/services/answer_call.rb`:

```ruby
class AnswerCall
  attr_reader :system_prompt, :user_prompt, :retrieved_chunks

  def initialize(system:, user:, retrieved_chunks: [])
    @system_prompt = system
    @user_prompt = user
    @retrieved_chunks = retrieved_chunks
  end
end
```

- [ ] **Step 2: NaiveAnswer**

`app/services/naive_answer.rb`:

```ruby
class NaiveAnswer
  def self.call(question:)
    AnswerCall.new(
      system: "You are a hockey rules expert. Answer the question concisely.",
      user: question
    )
  end
end
```

- [ ] **Step 3: BruteForceAnswer**

`app/services/brute_force_answer.rb`:

```ruby
class BruteForceAnswer
  RULEBOOK_TEXT = Rails.root.join("db/seeds/NHL_Rules_2024-25.md").read.freeze

  def self.call(question:)
    AnswerCall.new(
      system: "You are a hockey rules expert. Use the rulebook below to answer.",
      user: "<rulebook>\n#{RULEBOOK_TEXT}\n</rulebook>\n\nQuestion: #{question}"
    )
  end
end
```

- [ ] **Step 4: RagAnswer**

`app/services/rag_answer.rb`:

```ruby
class RagAnswer
  TOP_K = 3

  def self.call(question:)
    query_vector = OpenaiEmbed.embed(input: question)

    chunks = RuleChunk
      .nearest_neighbors(:embedding, query_vector, distance: :cosine)
      .limit(TOP_K)
      .to_a

    context = chunks.map { |c|
      label = c.rule_reference.presence || "Chunk #{c.chunk_index}"
      "[#{label}]\n#{c.content}"
    }.join("\n\n---\n\n")

    AnswerCall.new(
      system: "You are a hockey rules expert. Answer using only the excerpts below. If they don't contain the answer, say so plainly.",
      user: "<excerpts>\n#{context}\n</excerpts>\n\nQuestion: #{question}",
      retrieved_chunks: chunks.map { |c|
        {
          "chunk_index" => c.chunk_index,
          "rule_reference" => c.rule_reference,
          "content" => c.content,
          "similarity" => (1.0 - c.neighbor_distance.to_f).round(4)
        }
      }
    )
  end
end
```

- [ ] **Step 5: Smoke check all three**

```bash
bin/rails runner '
  q = "How long is a minor penalty?"
  a = NaiveAnswer.call(question: q)
  b = BruteForceAnswer.call(question: q)
  c = RagAnswer.call(question: q)
  puts "Naive user prompt length: #{a.user_prompt.length}"
  puts "BruteForce user prompt length: #{b.user_prompt.length}"
  puts "RAG retrieved: #{c.retrieved_chunks.length}; first sim=#{c.retrieved_chunks.first["similarity"]}"
'
```

Expected: Naive ~30 chars; BruteForce ~260k chars; RAG retrieved 3 chunks with similarities around 0.7–0.9.

- [ ] **Step 6: Commit**

```bash
git add app/services
git commit -m "Add NaiveAnswer, BruteForceAnswer, RagAnswer services"
```

---

## Task 8: GenerateAnswerJob with streaming + Turbo broadcast

**Files:**
- Create: `app/jobs/generate_answer_job.rb`

The Anthropic streaming API yields events; we accumulate the text, broadcast deltas via `Turbo::StreamsChannel`, and record timing/token data on completion.

- [ ] **Step 1: Write the job**

`app/jobs/generate_answer_job.rb`:

```ruby
class GenerateAnswerJob < ApplicationJob
  queue_as :default

  def perform(answer_id)
    answer = Answer.find(answer_id)
    answer.update!(status: "streaming", content: "")

    started_at = Time.current
    first_token_at = nil
    full_text = +""

    stream = AnthropicClient.client.messages.stream(
      model: AnthropicClient::MODEL,
      max_tokens: AnthropicClient::MAX_TOKENS,
      system: answer.system_prompt,
      messages: [{ role: "user", content: answer.user_prompt }]
    )

    stream.each do |event|
      case event.type
      when :message_start, "message_start"
        usage = event.message.usage rescue nil
        answer.update_columns(input_tokens: usage.input_tokens) if usage&.respond_to?(:input_tokens)
      when :content_block_delta, "content_block_delta"
        delta_text = event.delta.respond_to?(:text) ? event.delta.text : event.delta["text"]
        next unless delta_text
        first_token_at ||= Time.current
        full_text << delta_text
        Turbo::StreamsChannel.broadcast_append_to(
          answer.question,
          target: "answer_#{answer.id}_body",
          html: delta_text
        )
      when :message_delta, "message_delta"
        usage = event.usage rescue nil
        answer.update_columns(output_tokens: usage.output_tokens) if usage&.respond_to?(:output_tokens)
      end
    end

    total_ms = ((Time.current - started_at) * 1000).to_i
    ttft_ms = first_token_at ? ((first_token_at - started_at) * 1000).to_i : nil

    answer.update!(
      content: full_text,
      ttft_ms: ttft_ms,
      total_ms: total_ms,
      cost_cents: AnthropicClient.estimate_cost_cents(
        input_tokens: answer.input_tokens, output_tokens: answer.output_tokens
      ),
      status: "complete"
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      answer.question,
      target: "answer_#{answer.id}_meta",
      partial: "answers/meta",
      locals: { answer: answer.reload }
    )
  rescue => e
    Rails.logger.error("GenerateAnswerJob failed: #{e.class}: #{e.message}")
    Answer.where(id: answer_id).update_all(status: "failed", content: "ERROR: #{e.message}")
    raise
  end
end
```

Notes on SDK shape:
- The official `anthropic` gem exposes `client.messages.stream(...)` which returns an enumerable. Event types may be symbols or strings depending on version — the case statement handles both.
- If the gem in use accepts a block (`messages.stream(...) do |event| ... end`) instead of returning an enumerable, change `stream.each do |event|` to call the block form. Verify by running `bin/rails runner 'AnthropicClient.client.messages.method(:stream).source_location'` and checking the gem source.

- [ ] **Step 2: Commit**

```bash
git add app/jobs/generate_answer_job.rb
git commit -m "Add GenerateAnswerJob with streaming and Turbo broadcast"
```

(Smoke-test deferred to Task 11 — easier to test end-to-end via the controller.)

---

## Task 9: QuestionsController + routes

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/questions_controller.rb`

- [ ] **Step 1: Routes**

Replace `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :questions, only: %i[create show] do
    collection do
      get :new
    end
  end

  root "questions#new"
end
```

- [ ] **Step 2: Controller**

`app/controllers/questions_controller.rb`:

```ruby
class QuestionsController < ApplicationController
  def new
    @question = Question.new
  end

  def create
    @question = Question.create!(text: params.require(:question).permit(:text)[:text])

    create_answer(:naive,       NaiveAnswer.call(question: @question.text))
    create_answer(:brute_force, BruteForceAnswer.call(question: @question.text))
    create_answer(:rag,         RagAnswer.call(question: @question.text))

    @question.answers.each { |a| GenerateAnswerJob.perform_later(a.id) }

    redirect_to question_path(@question)
  end

  def show
    @question = Question.find(params[:id])
  end

  private

  def create_answer(mode, call)
    @question.answers.create!(
      mode: mode.to_s,
      system_prompt: call.system_prompt,
      user_prompt: call.user_prompt,
      retrieved_chunks: call.retrieved_chunks,
      status: "pending"
    )
  end
end
```

- [ ] **Step 3: Verify routes load**

```bash
bin/rails routes | grep questions
```

Expected: shows `POST /questions`, `GET /questions/:id`, `GET /questions/new`, and root pointing to `questions#new`.

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb app/controllers/questions_controller.rb
git commit -m "Add QuestionsController and routes"
```

---

## Task 10: Views — new form, show page, panel + meta partials

**Files:**
- Create: `app/views/questions/new.html.erb`
- Create: `app/views/questions/show.html.erb`
- Create: `app/views/answers/_panel.html.erb`
- Create: `app/views/answers/_meta.html.erb`
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: `app/views/questions/new.html.erb`**

```erb
<div class="page">
  <h1>Hockey Rules Q&A — three approaches</h1>
  <p class="lede">
    Ask any question about the NHL rulebook. We'll answer it three ways side-by-side:
    naive (no rulebook), brute force (the whole rulebook in the prompt), and RAG
    (top-3 retrieved chunks). Watch timing, tokens, and cost for each.
  </p>

  <%= form_with url: questions_path, method: :post, local: true, class: "ask-form" do |f| %>
    <%= f.fields_for :question, Question.new do |q| %>
      <%= q.text_area :text, placeholder: "How long is a minor penalty?", rows: 3, autofocus: true %>
    <% end %>
    <button type="submit">Ask</button>
  <% end %>

  <h2>Try one of these:</h2>
  <ul class="sample-questions">
    <li>How long is a minor penalty?</li>
    <li>What is the penalty for using a broken stick?</li>
    <li>How big is the goal crease in metric units?</li>
    <li>What's the difference between icing and offside?</li>
    <li>Can a goalie score a goal?</li>
    <li>Is it legal to use a baseball bat?</li>
    <li>What does Rule 22.1 say?</li>
  </ul>
</div>
```

- [ ] **Step 2: `app/views/questions/show.html.erb`**

```erb
<%= turbo_stream_from @question %>

<div class="page">
  <h1>Hockey Rules Q&A</h1>
  <p class="question-text"><strong>Q:</strong> <%= @question.text %></p>
  <p><%= link_to "← Ask another", new_questions_path %></p>

  <div class="three-panel">
    <% @question.answers.order(:mode).each do |answer| %>
      <%= render "answers/panel", answer: answer %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 3: `app/views/answers/_panel.html.erb`**

```erb
<% mode_explanations = {
  "naive"       => "Just asks Claude with no rulebook context. Fast, cheap, often wrong on specifics.",
  "brute_force" => "Stuffs the entire ~260KB rulebook into the prompt every time. Accurate but expensive.",
  "rag"         => "Embeds the question, finds the top-3 nearest chunks via pgvector, sends only those."
} %>

<section class="panel panel-<%= answer.mode %>" id="answer_<%= answer.id %>">
  <header>
    <h2><%= answer.display_name %></h2>
    <p class="explanation"><%= mode_explanations[answer.mode] %></p>
  </header>

  <div id="answer_<%= answer.id %>_body" class="body">
    <%= answer.content %>
  </div>

  <div id="answer_<%= answer.id %>_meta" class="meta">
    <%= render "answers/meta", answer: answer %>
  </div>

  <% if answer.mode == "rag" && answer.retrieved_chunks.any? %>
    <details class="retrieved-chunks">
      <summary>Retrieved chunks (what got sent to the model)</summary>
      <% answer.retrieved_chunks.each do |chunk| %>
        <div class="chunk">
          <strong><%= chunk["rule_reference"].presence || "Chunk #{chunk["chunk_index"]}" %></strong>
          <span class="similarity">similarity: <%= chunk["similarity"]&.round(2) %></span>
          <pre><%= chunk["content"] %></pre>
        </div>
      <% end %>
    </details>
  <% end %>
</section>
```

- [ ] **Step 4: `app/views/answers/_meta.html.erb`**

```erb
<dl class="metrics">
  <% if answer.status == "pending" %>
    <dt>Status</dt><dd>queued…</dd>
  <% elsif answer.status == "streaming" %>
    <dt>Status</dt><dd>streaming…</dd>
  <% elsif answer.status == "failed" %>
    <dt>Status</dt><dd class="failed">failed</dd>
  <% else %>
    <dt>Time to first token</dt><dd><%= answer.ttft_ms %> ms</dd>
    <dt>Total time</dt>          <dd><%= answer.total_ms %> ms</dd>
    <dt>Input tokens</dt>        <dd><%= number_with_delimiter(answer.input_tokens.to_i) %></dd>
    <dt>Output tokens</dt>       <dd><%= number_with_delimiter(answer.output_tokens.to_i) %></dd>
    <dt>Cost</dt>                <dd>¢<%= answer.cost_cents %></dd>
  <% end %>
</dl>
```

- [ ] **Step 5: Update layout for Turbo + simple CSS load**

Verify `app/views/layouts/application.html.erb` includes `<%= turbo_include_tags %>` (importmap default does) and `<%= stylesheet_link_tag "application" %>`. If missing, add inside `<head>`.

- [ ] **Step 6: Commit**

```bash
git add app/views config/routes.rb
git commit -m "Add views for new/show, panel and meta partials"
```

---

## Task 11: Wire it all up — end-to-end smoke test

**Files:** None new.

- [ ] **Step 1: Start the dev server with Solid Queue**

Rails 8 default runs Solid Queue in-process with `bin/dev`. If `bin/dev` doesn't exist, run in two terminals (dotenv-rails autoloads `.env`):

```bash
bin/rails server
bin/jobs start
```

- [ ] **Step 2: Open http://localhost:3000 in a browser**

Type "How long is a minor penalty?" and submit.

Expected:
- Redirects to `/questions/<id>`
- Three panels appear, each showing "queued…" or "streaming…"
- Within ~2s, the Naive and RAG answers begin streaming token-by-token via Turbo
- The Brute Force panel takes longer to start (large prompt, ~80k tokens) and streams a longer answer
- When each completes, the meta block flips to show ttft, total time, tokens, cost
- The RAG panel shows a `<details>` block with three retrieved chunks and similarity scores

- [ ] **Step 3: Watch logs for errors**

Tail the Rails log and the jobs log. Expected: no exceptions. If Voyage or Anthropic errors appear, fix configuration before proceeding.

- [ ] **Step 4: Verify a chunk-citation question**

Submit "What does Rule 22.1 say?". RAG should retrieve a chunk whose `rule_reference` is "Rule 22.1" or similar; the answer should quote it.

- [ ] **Step 5: Commit** (only if any fixes were needed)

If fixes were made:
```bash
git add -A
git commit -m "Fix end-to-end streaming wiring"
```

---

## Task 12: Minimal CSS to make the three-panel layout readable

**Files:**
- Create or modify: `app/assets/stylesheets/application.css`

The spec says "Tailwind for the minimal UI" but Rails 8 default uses Propshaft + raw CSS. Tailwind would add a dependency and a build step. For a demo, raw CSS is faster — keep it small (~80 lines).

- [ ] **Step 1: Write the stylesheet**

`app/assets/stylesheets/application.css`:

```css
*, *::before, *::after { box-sizing: border-box; }

body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  margin: 0;
  background: #f8f9fb;
  color: #1a1a1a;
  line-height: 1.5;
}

.page { max-width: 1400px; margin: 0 auto; padding: 24px; }

h1 { margin: 0 0 8px; font-size: 28px; }
h2 { margin: 0 0 8px; font-size: 18px; }

.lede { color: #555; margin: 0 0 24px; max-width: 720px; }

.ask-form textarea {
  width: 100%; padding: 12px; font: inherit; font-size: 16px;
  border: 1px solid #ccc; border-radius: 6px; resize: vertical;
}
.ask-form button {
  margin-top: 8px; padding: 10px 20px; font: inherit; font-weight: 600;
  background: #1a73e8; color: white; border: 0; border-radius: 6px; cursor: pointer;
}
.ask-form button:hover { background: #155bb5; }

.sample-questions { color: #555; padding-left: 20px; }
.sample-questions li { margin: 4px 0; }

.question-text {
  background: #fff; padding: 16px; border-radius: 8px;
  border: 1px solid #e0e3e8; margin: 16px 0;
}

.three-panel {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 16px;
  margin-top: 16px;
}

@media (max-width: 1100px) {
  .three-panel { grid-template-columns: 1fr; }
}

.panel {
  background: #fff; border: 1px solid #e0e3e8; border-radius: 8px;
  padding: 16px; display: flex; flex-direction: column;
}
.panel-naive       { border-top: 4px solid #b91c1c; }
.panel-brute_force { border-top: 4px solid #ca8a04; }
.panel-rag         { border-top: 4px solid #15803d; }

.panel .explanation { color: #666; font-size: 13px; margin: 4px 0 16px; }

.panel .body {
  background: #fafafa; padding: 12px; border-radius: 6px;
  white-space: pre-wrap; min-height: 80px; font-size: 14px;
  margin-bottom: 12px;
}

.metrics { display: grid; grid-template-columns: auto 1fr; gap: 4px 16px; font-size: 13px; margin: 0; }
.metrics dt { color: #555; }
.metrics dd { margin: 0; font-variant-numeric: tabular-nums; }
.metrics .failed { color: #b91c1c; }

.retrieved-chunks { margin-top: 12px; font-size: 13px; }
.retrieved-chunks summary { cursor: pointer; color: #1a73e8; }
.retrieved-chunks .chunk { margin-top: 8px; padding: 8px; background: #f4f6f9; border-radius: 4px; }
.retrieved-chunks .similarity { color: #666; margin-left: 8px; }
.retrieved-chunks pre { white-space: pre-wrap; margin: 4px 0 0; font-size: 12px; color: #333; }
```

- [ ] **Step 2: Reload the page**

Expected: three columns on wide screens, stacked on narrow screens; colored top borders by mode; readable metrics.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "Add minimal CSS for three-panel demo layout"
```

---

## Task 13: Demo polish and run through sample questions

- [ ] **Step 1: Run the seven sample questions from the spec**

For each question in the spec's "Sample questions to demo" table, submit and confirm the three panels behave roughly as the table predicts. Note any failures.

- [ ] **Step 2: If RAG misses on a question, adjust**

Common knobs: `CHUNK_SIZE` (currently 500), `CHUNK_OVERLAP` (currently 100), or `TOP_K` in `RagAnswer` (currently 3). Re-run `IngestRulebookTask.call` if you change chunk size. Pick one knob; don't over-tune — the failure modes are themselves teaching moments.

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "Tune chunking after demo dry-run" --allow-empty
```

(Use `--allow-empty` only if nothing changed — a marker commit for "demo ready".)

---

## Self-Review Notes

**Spec coverage check:**
- ✅ Three modes (Naive/Brute Force/RAG) — Task 7
- ✅ Schema with pgvector, three tables — Task 2
- ✅ Streaming + timing/token/cost — Task 8
- ✅ Turbo broadcast — Tasks 8 + 10
- ✅ Retrieved-chunks display — Task 10
- ✅ Ingestion task reading **markdown** (the user's deviation #1) — Task 6
- ✅ OpenAI embeddings instead of Voyage (the user's deviation #2) — Tasks 2, 3, 4, 6, 7
- ✅ Sample questions in UI — Task 10
- ✅ Minimal CSS / 3-panel layout — Task 12
- ⚠ Spec mentions Tailwind; we chose raw CSS for demo speed. Documented in Task 12.
- ⚠ Spec uses `answer.update!` inside the streaming loop; we use `update_columns` to skip validations and timestamp churn during high-frequency stream events.
- ⚠ Spec uses Hash-style retrieved_chunks; we serialize chunk attributes (incl. similarity = 1 - cosine_distance) into the jsonb column at service-call time so the view can render without re-querying.

**Placeholder scan:** No TBDs, no "appropriate error handling", no "similar to Task N". Every code block is complete.

**Type consistency:** `AnswerCall#system_prompt/user_prompt/retrieved_chunks` consistent across services and the job. `mode` strings ("naive", "brute_force", "rag") consistent across model, services, controller, view, and CSS class names.

**Open risk:** The exact event-shape from the `anthropic` Ruby SDK's streaming API depends on gem version. Task 8 calls this out and the case statement handles both symbol/string keys and missing-attribute cases. If the gem-version mismatch breaks streaming, fall back to non-streaming `messages.create` and broadcast the full text once at completion (graceful degradation; loses TTFT measurement).
