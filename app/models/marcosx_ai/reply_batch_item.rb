class MarcosxAi::ReplyBatchItem < ApplicationRecord
  self.table_name = 'marcosx_ai_reply_batch_items'
  belongs_to :reply_batch, class_name: 'MarcosxAi::ReplyBatch'
  belongs_to :conversation
  has_one_attached :audio

  def public_data
    audio_path = Rails.application.routes.url_helpers.rails_blob_path(audio, only_path: true) if audio.attached?
    { id: id, conversation_id: conversation.display_id, name: conversation.contact.name, avatar_url: conversation.contact.avatar_url,
      status: status, reason: reason, plan: plan, audio_url: audio_path,
      resources: reply_batch.assistant.resources.where(id: plan['resource_ids']).map { |r| { title: r.title, kind: r.kind } },
      pix: reply_batch.assistant.pix_keys.find_by(id: plan['pix_key_id'])&.title }
  end

  def discard!
    state = MarcosxAi::ConversationState.find_by(conversation_id: conversation_id)
    state&.with_lock do
      if state.metadata['reply_batch_item_id'] == id
        state.update!(metadata: state.metadata.except('reply_batch_item_id', 'approved_draft', 'pending_response', 'presence_media').merge(
          'processing' => false, 'run_token' => SecureRandom.uuid
        ))
      end
    end
    with_lock { update!(status: 'discarded') unless status.in?(%w[sent skipped failed]) }
  end
end
