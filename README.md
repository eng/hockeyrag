# Hockey Rules RAG Demo

A 600-line Rails 8 app for the engineering team. Answers questions about the NHL rulebook three ways side-by-side and shows the timing, token count, and cost of each. Designed to give every engineer hands-on intuition for embeddings, chunking, and vector retrieval.

| Mode | Approach | Typical cost per question |
|---|---|---|
| **Naive** | Ask Claude with no rulebook context | ~¢0.03 |
| **Brute Force** | Stuff the entire ~260KB rulebook into the prompt | ~¢21 |
| **RAG** | Embed the question, retrieve top-3 chunks via pgvector | ~¢0.33 |

The RAG panel exposes the retrieved chunks (and their cosine similarities) so the audience can see what actually got sent to the model — and reason about when retrieval helped or hurt.

## Stack

- Rails 8.1 / Ruby 4.0
- Postgres 17 + [pgvector](https://github.com/pgvector/pgvector) via the [`neighbor`](https://github.com/ankane/neighbor) gem (1536-dim cosine HNSW)
- OpenAI `text-embedding-3-small` for embeddings
- Anthropic `claude-sonnet-4-6` for chat (streamed via `Anthropic::Client#messages.stream`)
- Turbo Streams for per-token live updates
- Solid Queue (runs in-process via `:async` adapter in dev)

## Setup

1. **pgvector on Postgres 17.** The Homebrew `pgvector` bottle ships for Postgres 17/18:

   ```sh
   brew install postgresql@17 pgvector
   # Edit /opt/homebrew/var/postgresql@17/postgresql.conf to set `port = 5433`
   # so it can run alongside other Postgres versions.
   brew services start postgresql@17
   ```

2. **API keys.** Copy `.env.example` to `.env` and fill in:

   ```
   OPENAI_API_KEY=sk-...
   ANTHROPIC_API_KEY=sk-ant-...
   ```

3. **Bundle, create DB, migrate, ingest.**

   ```sh
   bundle install
   bin/rails db:create db:migrate
   bin/rails runner 'IngestRulebookTask.call'   # ~655 chunks, ~$0.002 of embeddings
   ```

4. **Run.**

   ```sh
   bin/rails server
   open http://localhost:3000
   ```

## Where the interesting code lives

- `app/tasks/ingest_rulebook_task.rb` — reads `db/seeds/NHL_Rules_2024-25.md`, chunks at 500 chars / 100 overlap, batches embedding requests.
- `app/services/rag_answer.rb` — does the nearest-neighbor lookup and packages the top-3 chunks into the user prompt.
- `app/services/brute_force_answer.rb` — passes the entire rulebook in the prompt.
- `app/jobs/generate_answer_job.rb` — streams Claude's response and broadcasts each text delta over Turbo.
- `app/views/answers/_panel.html.erb` — renders one mode's column, including the retrieved-chunks `<details>` block.

## What this demo is NOT

Not production-ready. No auth, no rate limiting, no error handling beyond the happy path. The point is that 600 lines of readable Ruby is more instructive than a polished framework.

See `docs/superpowers/plans/2026-05-13-hockey-rag-demo.md` for the implementation plan and rationale.
