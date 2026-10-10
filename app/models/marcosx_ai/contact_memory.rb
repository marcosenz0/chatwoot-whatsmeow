class MarcosxAi::ContactMemory < ApplicationRecord
  self.table_name = 'marcosx_ai_contact_memories'
  belongs_to :account
  belongs_to :contact
  validates :contact_id, uniqueness: { scope: :account_id }
  validate :same_account

  CACHE_KEYS = %w[conversation_summary summary_cursor summary_signature summary_messages_count summary_updated_at
                  summary_manually_edited memory_rebuild pending_response analysis approved_draft].freeze

  def self.apply(scope, conversation)
    memory = find_by(account_id: conversation.account_id, contact_id: conversation.contact_id)
    return scope unless memory

    scope = scope.where('messages.id > ? AND messages.created_at > ?', memory.cutoff_message_id, memory.forgotten_at) if memory.forgotten_at
    memory.excluded_message_ids.empty? ? scope : scope.where.not(id: memory.excluded_message_ids)
  end

  def forget!
    transaction do
      lock!
      update!(forgotten_at: Time.current, cutoff_message_id: account.messages.where(conversation_id: conversations.select(:id)).maximum(:id) || 0,
              excluded_message_ids: [])
      states = MarcosxAi::ConversationState.where(account: account, conversation_id: conversations.select(:id))
      states.each { |state| invalidate!(state, remove_links: true) }
      ids = conversations.pluck(:id)
      MarcosxAi::ConversationState.where(account: account).where("metadata -> 'approved_context_links' IS NOT NULL").find_each do |state|
        next unless state.metadata.fetch('approved_context_links', []).any? { |entry| ids.include?(entry['conversation_id']) }

        state.with_lock do
          remaining = state.metadata.fetch('approved_context_links', []).reject { |entry| ids.include?(entry['conversation_id']) }
          invalidate!(state)
          state.update!(metadata: state.metadata.merge('approved_context_links' => remaining))
        end
      end
    end
  end

  def exclude!(message, restore: false)
    with_lock do
      ids = excluded_message_ids - [message.id]
      ids << message.id unless restore
      update!(excluded_message_ids: ids)
      state = MarcosxAi::ConversationState.find_by(conversation: message.conversation)
      invalidate!(state) if state
      invalidate_dependents!(message.conversation_id)
    end
  end

  def invalidate!(state, remove_links: false)
    state.with_lock do
      metadata = state.metadata.except(*CACHE_KEYS)
      metadata = metadata.except('approved_context_links') if remove_links
      state.update!(metadata: metadata.merge('run_token' => SecureRandom.uuid, 'processing' => false))
    end
  end

  def invalidate_dependents!(conversation_id)
    MarcosxAi::ConversationState.where(account: account).where("metadata -> 'approved_context_links' IS NOT NULL").find_each do |state|
      links = state.metadata.fetch('approved_context_links', [])
      invalidate!(state) if links.any? { |entry| entry['conversation_id'] == conversation_id }
    end
  end

  private

  def conversations
    account.conversations.where(contact: contact)
  end

  def same_account
    errors.add(:contact, 'must belong to the account') if contact && contact.account_id != account_id
  end
end
