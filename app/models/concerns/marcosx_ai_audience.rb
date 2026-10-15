module MarcosxAiAudience
  extend ActiveSupport::Concern

  included do
    belongs_to :conversation, optional: true
    validates :audience, inclusion: { in: %w[global conversation contacts] }
    validate :valid_audience

    scope :available_to, lambda { |conversation|
      if conversation
        where(account_id: conversation.account_id).where(
          "audience = 'global' OR (audience = 'conversation' AND conversation_id = :conversation) OR " \
          "(audience = 'contacts' AND contact_ids @> :contacts::jsonb)",
          conversation: conversation.id, contacts: [conversation.contact_id].to_json
        )
      else
        where(audience: 'global')
      end
    }
  end

  def audience_data
    { audience: audience, contact_ids: contact_ids,
      audience_contacts: account.contacts.where(id: contact_ids).order(:name, :id).map { |contact| { id: contact.id, name: contact.name } },
      conversation_id: conversation&.display_id, conversation_name: conversation&.contact&.name }
  end

  private

  def valid_audience
    ids_valid = contact_ids.is_a?(Array) && contact_ids.size <= 200 && contact_ids.uniq == contact_ids &&
                contact_ids.all? { |id| id.is_a?(Integer) && id.positive? }
    valid = case audience
            when 'global' then conversation_id.nil? && contact_ids == []
            when 'conversation' then conversation.present? && conversation.account_id == account_id && contact_ids == []
            when 'contacts'
              conversation_id.nil? && ids_valid && contact_ids.present? && account.contacts.where(id: contact_ids).count == contact_ids.size
            end
    errors.add(:audience, :invalid) unless valid
  end
end
