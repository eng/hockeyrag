class AnswerCall
  attr_reader :system_prompt, :user_prompt, :retrieved_chunks

  def initialize(system:, user:, retrieved_chunks: [])
    @system_prompt = system
    @user_prompt = user
    @retrieved_chunks = retrieved_chunks
  end
end
