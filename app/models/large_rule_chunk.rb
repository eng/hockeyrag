class LargeRuleChunk < ApplicationRecord
  has_neighbors :embedding, dimensions: 3072
end
