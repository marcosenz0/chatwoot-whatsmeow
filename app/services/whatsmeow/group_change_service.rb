class Whatsmeow::GroupChangeService
  pattr_initialize [:inbox!, :params!]

  def perform
    conversation.contact.update!(name: params['group_name']) if params['name_changed']
    return if inbox.messages.exists?(source_id: source_id)

    conversation.messages.create!(account_id: inbox.account_id, inbox_id: inbox.id, source_id: source_id, message_type: :activity,
                                  content: change_content, content_attributes: { whatsmeow_group_change: true },
                                  created_at: Time.zone.at(params.fetch('timestamp').to_i))
  end

  private

  def conversation
    @conversation ||= Whatsmeow::GroupConversationBuilder.new(inbox: inbox, params: params.with_indifferent_access).perform
  end

  def source_id
    @source_id ||= "whatsmeow-group-change:#{Digest::SHA256.hexdigest(params.slice('group_jid', 'timestamp', 'version', 'changes').to_json)}"
  end

  def change_content
    I18n.with_locale(inbox.account.locale) do
      params.fetch('changes').map do |change|
        I18n.t("whatsmeow.group_changes.#{change.fetch('kind')}", names: change['names'], name: params['group_name'])
      end.join("\n")
    end
  end
end
