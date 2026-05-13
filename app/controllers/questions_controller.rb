class QuestionsController < ApplicationController
  def new
    @question = Question.new
  end

  def create
    @question = Question.create!(text: question_params[:text])

    build_answer(:naive,       NaiveAnswer.call(question: @question.text))
    build_answer(:brute_force, BruteForceAnswer.call(question: @question.text))
    build_answer(:rag,         RagAnswer.call(question: @question.text))

    @question.answers.each { |a| GenerateAnswerJob.perform_later(a.id) }

    redirect_to question_path(@question)
  end

  def show
    @question = Question.find(params[:id])
  end

  private

  def question_params
    params.require(:question).permit(:text)
  end

  def build_answer(mode, call)
    @question.answers.create!(
      mode: mode.to_s,
      system_prompt: call.system_prompt,
      user_prompt: call.user_prompt,
      retrieved_chunks: call.retrieved_chunks,
      status: "pending"
    )
  end
end
