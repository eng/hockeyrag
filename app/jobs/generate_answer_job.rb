class GenerateAnswerJob < ApplicationJob
  queue_as :default

  def perform(answer_id)
    answer = Answer.find(answer_id)
    answer.update!(status: "streaming", content: "")

    started_at = Time.current
    first_token_at = nil
    full_text = +""

    stream = AnthropicClient.client.messages.stream(
      model: AnthropicClient::MODEL,
      max_tokens: AnthropicClient::MAX_TOKENS,
      system: answer.system_prompt,
      messages: [{ role: "user", content: answer.user_prompt }]
    )

    stream.each do |event|
      case event.type
      when :message_start
        usage = event.message&.usage
        answer.update_columns(input_tokens: usage.input_tokens) if usage
      when :text
        first_token_at ||= Time.current
        delta_text = event.text.to_s
        next if delta_text.empty?
        full_text << delta_text
        Turbo::StreamsChannel.broadcast_append_to(
          [ answer.question, "answers" ],
          target: "answer_#{answer.id}_body",
          html: delta_text
        )
      when :message_delta
        usage = event.usage
        answer.update_columns(output_tokens: usage.output_tokens) if usage&.respond_to?(:output_tokens)
      end
    end

    total_ms = ((Time.current - started_at) * 1000).to_i
    ttft_ms = first_token_at ? ((first_token_at - started_at) * 1000).to_i : nil

    answer.update!(
      content: full_text,
      ttft_ms: ttft_ms,
      total_ms: total_ms,
      cost_cents: AnthropicClient.estimate_cost_cents(
        input_tokens: answer.input_tokens, output_tokens: answer.output_tokens
      ),
      status: "complete"
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ answer.question, "answers" ],
      target: "answer_#{answer.id}_meta",
      partial: "answers/meta",
      locals: { answer: answer.reload }
    )
  rescue => e
    Rails.logger.error("GenerateAnswerJob failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    Answer.where(id: answer_id).update_all(status: "failed", content: "ERROR: #{e.message}")
    Turbo::StreamsChannel.broadcast_replace_to(
      [ Answer.find(answer_id).question, "answers" ],
      target: "answer_#{answer_id}_meta",
      partial: "answers/meta",
      locals: { answer: Answer.find(answer_id) }
    )
    raise
  end
end
