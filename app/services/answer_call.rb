class AnswerCall
  attr_reader :system_prompt, :user_prompt, :retrieved_chunks, :aux_cost_cents, :aux_description

  def initialize(system:, user:, retrieved_chunks: [], aux_cost_cents: 0.0, aux_description: nil)
    @system_prompt = system
    @user_prompt = user
    @retrieved_chunks = retrieved_chunks
    @aux_cost_cents = aux_cost_cents
    @aux_description = aux_description
  end
end
