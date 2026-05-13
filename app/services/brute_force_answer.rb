class BruteForceAnswer
  RULEBOOK_TEXT = Rails.root.join("db/seeds/NHL_Rules_2024-25.md").read.freeze

  def self.call(question:)
    AnswerCall.new(
      system: "You are a hockey rules expert. Use the rulebook below to answer.",
      user: "<rulebook>\n#{RULEBOOK_TEXT}\n</rulebook>\n\nQuestion: #{question}"
    )
  end
end
