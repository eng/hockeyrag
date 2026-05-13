class Question < ApplicationRecord
  RAG_STRATEGIES = %w[fixed structured].freeze

  has_many :answers, dependent: :destroy

  validates :text, presence: true
  validates :rag_strategy, inclusion: { in: RAG_STRATEGIES }

  def rag_strategy_label
    case rag_strategy
    when "fixed"      then "fixed-length 500-char chunks"
    when "structured" then "structure-aware chunks (split by rule)"
    end
  end
end
