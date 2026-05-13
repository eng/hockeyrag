class QuestionsController < ApplicationController
  def new
    @question = Question.new
  end

  def create
    @question = Question.create!(question_params)

    build_answer(:naive,       NaiveAnswer.call(question: @question.text))
    build_answer(:brute_force, BruteForceAnswer.call(question: @question.text))
    build_answer(:rag,         RagAnswer.call(question: @question.text, strategy: @question.rag_strategy))

    @question.answers.each { |a| GenerateAnswerJob.perform_later(a.id) }

    redirect_to question_path(@question)
  end

  def show
    @question = Question.find(params[:id])
  end

  private

  def question_params
    params.require(:question).permit(:text, :rag_strategy)
  end

  def build_answer(mode, call)
    @question.answers.create!(
      mode: mode.to_s,
      system_prompt: call.system_prompt,
      user_prompt: call.user_prompt,
      retrieved_chunks: call.retrieved_chunks,
      aux_cost_cents: call.aux_cost_cents.to_f,
      aux_description: call.aux_description,
      status: "pending"
    )
  end
end
