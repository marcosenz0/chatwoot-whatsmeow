class Pipelines::RemoveConversationService
  pattr_initialize [:account!, :conversation!]

  def perform
    raise ActiveRecord::RecordNotFound unless conversation.account_id == account.id

    conversation.update!(
      conversation_pipeline: nil,
      conversation_pipeline_stage: nil,
      pipeline_stage_entered_at: nil
    )
    conversation
  end
end
