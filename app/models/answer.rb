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
