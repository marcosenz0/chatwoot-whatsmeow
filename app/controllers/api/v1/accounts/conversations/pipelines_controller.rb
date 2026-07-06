class Api::V1::Accounts::Conversations::PipelinesController < Api::V1::Accounts::Conversations::BaseController
  def create
    @conversation = Pipelines::MoveConversationService.new(
      account: Current.account,
      conversation: @conversation,
      stage: pipeline_stage
    ).perform
    render 'api/v1/accounts/conversations/show'
  end

  def destroy
    @conversation = Pipelines::RemoveConversationService.new(
      account: Current.account,
      conversation: @conversation
    ).perform
    render 'api/v1/accounts/conversations/show'
  end

  private

  def pipeline_stage
    Current.account.conversation_pipeline_stages.active.find(params[:pipeline_stage_id])
  end
end
