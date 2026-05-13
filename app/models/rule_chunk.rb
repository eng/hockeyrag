class RuleChunk < ApplicationRecord
  has_neighbors :embedding, dimensions: 1536
end
