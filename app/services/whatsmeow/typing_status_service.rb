class Whatsmeow::TypingStatusService
  include Events::Types

  def self.apply_incoming(inbox:, params:)
    new(inbox: inbox, params: params).apply_incoming
  end

  def initialize(conversation: nil, status: nil, inbox: nil, params: nil)
    @conversation = conversation
    @status = status
    @inbox = inbox
    @params = params&.with_indifferent_access
  end

  def perform
    return unless outbound_typing_enabled?

    Whatsmeow::SessionClient.new(inbox: conversation.inbox).typing(
      to: target_identifier,
      state: status == 'on' ? 'composing' : 'paused'
    )
  rescue Whatsmeow::SessionClient::Error => e
    Rails.logger.warn("Whatsmeow: failed to send typing status for conversation #{conversation.id}: #{e.message}")
  end

  def apply_incoming
    return unless incoming_typing_enabled?

    conversation = incoming_conversation
    return if conversation.blank?

    event = incoming_event
    return if event.blank?

    Rails.configuration.dispatcher.dispatch(
      event,
      Time.zone.now,
      conversation: conversation,
      user: incoming_typing_user(conversation),
      is_private: false
    )
  end

  private

  attr_reader :conversation, :status, :inbox, :params

  def outbound_typing_enabled?
    return false unless conversation&.inbox&.channel_type == 'Channel::Whatsmeow'
    return false unless %w[on off].include?(status)

    conversation.inbox.channel.typing_enabled?
  end

  def incoming_typing_enabled?
    inbox&.channel_type == 'Channel::Whatsmeow' && inbox.channel.typing_enabled?
  end

  def target_identifier
    source_id = conversation.contact_inbox&.source_id.to_s.strip
    return source_id if source_id.include?('@')

    digits = source_id.delete('^0-9')
    return "#{digits}@s.whatsapp.net" if digits.match?(/\A[1-9]\d{1,14}\z/)

    raise Whatsmeow::SessionClient::Error, "No WhatsApp target found for conversation #{conversation.id}"
  end

  def incoming_event
    case params[:state]
    when 'composing'
      CONVERSATION_TYPING_ON
    when 'paused'
      CONVERSATION_TYPING_OFF
    end
  end

  def incoming_conversation
    contact_inbox = inbox.contact_inboxes.find_by(source_id: conversation_source_ids)
    return if contact_inbox.blank?

    conversations = inbox.conversations.where(contact_inbox_id: contact_inbox.id)
    conversations.where.not(status: :resolved).order(created_at: :desc).first || conversations.order(created_at: :desc).first
  end

  def incoming_typing_user(conversation)
    return conversation.contact unless ActiveModel::Type::Boolean.new.cast(params[:is_group])

    participant = inbox.contact_inboxes.find_by(source_id: participant_source_ids)
    participant&.contact || conversation.contact
  end

  def conversation_source_ids
    source_ids = ActiveModel::Type::Boolean.new.cast(params[:is_group]) ? [params[:chat]] : direct_source_ids
    source_ids.compact_blank.uniq
  end

  def direct_source_ids
    [
      params[:contact_jid],
      params[:contact_alt_jid],
      params[:contact_lid_jid],
      params[:sender_alt],
      params[:sender],
      params[:chat],
      params[:recipient_alt]
    ]
  end

  def participant_source_ids
    [params[:contact_jid], params[:contact_alt_jid], params[:contact_lid_jid], params[:sender_alt], params[:sender]].compact_blank.uniq
  end
end
