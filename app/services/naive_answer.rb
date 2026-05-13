class NaiveAnswer
  def self.call(question:)
    AnswerCall.new(
      system: "You are a hockey rules expert. Answer the question concisely.",
      user: question
    )
  end
end
