class AddAuxCostToAnswers < ActiveRecord::Migration[8.1]
  def change
    add_column :answers, :aux_cost_cents, :decimal, precision: 8, scale: 4, default: 0, null: false
    add_column :answers, :aux_description, :string
  end
end
