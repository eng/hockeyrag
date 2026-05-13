require "anthropic"

module AnthropicClient
  MODEL = "claude-sonnet-4-6".freeze
  HAIKU_MODEL = "claude-haiku-4-5-20251001".freeze
  MAX_TOKENS = 800

  # Sonnet 4.6 pricing (as of 2026-05): $3 / 1M input tokens, $15 / 1M output tokens.
  INPUT_COST_PER_TOKEN_CENTS  = 300.0 / 1_000_000  # 0.0003 cents/token
  OUTPUT_COST_PER_TOKEN_CENTS = 1500.0 / 1_000_000 # 0.0015 cents/token

  # Haiku 4.5 pricing: $1 / 1M input, $5 / 1M output.
  HAIKU_INPUT_COST_PER_TOKEN_CENTS  = 100.0 / 1_000_000
  HAIKU_OUTPUT_COST_PER_TOKEN_CENTS = 500.0 / 1_000_000

  def self.client
    @client ||= Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))
  end

  def self.estimate_cost_cents(input_tokens:, output_tokens:)
    cents = input_tokens.to_i * INPUT_COST_PER_TOKEN_CENTS +
            output_tokens.to_i * OUTPUT_COST_PER_TOKEN_CENTS
    cents.round(4)
  end

  def self.estimate_haiku_cost_cents(input_tokens:, output_tokens:)
    cents = input_tokens.to_i * HAIKU_INPUT_COST_PER_TOKEN_CENTS +
            output_tokens.to_i * HAIKU_OUTPUT_COST_PER_TOKEN_CENTS
    cents.round(4)
  end
end
