require "faraday"
require "json"

module OpenaiEmbed
  ENDPOINT = "https://api.openai.com/v1/embeddings".freeze
  MODEL = "text-embedding-3-small".freeze # 1536 dims, ~$0.02 per 1M tokens

  class Error < StandardError; end

  def self.embed(input:, model: MODEL)
    response = connection.post("") do |req|
      req.headers["Authorization"] = "Bearer #{api_key}"
      req.headers["Content-Type"] = "application/json"
      req.body = JSON.generate(model: model, input: Array(input))
    end

    raise Error, "OpenAI #{response.status}: #{response.body}" unless response.success?

    body = JSON.parse(response.body)
    vectors = body.fetch("data").sort_by { |d| d["index"] }.map { |d| d.fetch("embedding") }
    input.is_a?(Array) ? vectors : vectors.first
  end

  def self.connection
    @connection ||= Faraday.new(url: ENDPOINT) do |f|
      f.adapter Faraday.default_adapter
      f.options.timeout = 60
    end
  end

  def self.api_key
    ENV.fetch("OPENAI_API_KEY")
  end
end
