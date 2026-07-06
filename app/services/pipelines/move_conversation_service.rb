class Pipelines::MoveConversationService
  pattr_initialize [:account!, :conversation!, :stage!]

  def perform
    raise ActiveRecord::RecordNotFound unless conversation.account_id == account.id
    raise ActiveRecord::RecordNotFound unless stage.account_id == account.id

    conversation.update!(
      conversation_pipeline: stage.conversation_pipeline,
      conversation_pipeline_stage: stage,
      pipeline_stage_entered_at: Time.current
    )
    conversation
  end
end
