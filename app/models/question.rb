class Question < ApplicationRecord
  has_many :answers, dependent: :destroy

  validates :text, presence: true
end
