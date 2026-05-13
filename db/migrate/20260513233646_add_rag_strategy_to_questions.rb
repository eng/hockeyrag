class AddRagStrategyToQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :questions, :rag_strategy, :string, default: "fixed", null: false
  end
end
