class StructuredRuleChunk < ApplicationRecord
  has_neighbors :embedding, dimensions: 1536
end
