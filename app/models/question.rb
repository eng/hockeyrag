class Question < ApplicationRecord
  RAG_STRATEGIES = %w[fixed structured hybrid rerank hyde large_embedding hybrid_rerank].freeze

  RAG_STRATEGY_LABELS = {
    "fixed"           => "fixed-length 500-char chunks",
    "structured"      => "structure-aware chunks (split by rule)",
    "hybrid"          => "hybrid search (BM25 + cosine, RRF merge)",
    "rerank"          => "cosine top-15 → Haiku reranks to top 3",
    "hyde"            => "HyDE — Haiku hypothetical answer, then search",
    "large_embedding" => "text-embedding-3-large (3072 dims)",
    "hybrid_rerank"   => "hybrid retrieval → Haiku rerank (production recipe)"
  }.freeze

  has_many :answers, dependent: :destroy

  validates :text, presence: true
  validates :rag_strategy, inclusion: { in: RAG_STRATEGIES }

  def rag_strategy_label
    RAG_STRATEGY_LABELS[rag_strategy]
  end
end
