class Whatsmeow::DeleteMessageService
  def self.apply_incoming(inbox:, params:)
    new(inbox: inbox, params: params).apply_incoming
  end

  def initialize(message: nil, actor: nil, inbox: nil, params: nil)
    @message = message
    @actor = actor
    @inbox = inbox
    @params = params&.with_indifferent_access
  end

  def perform
    validate_outgoing_delete!

    dispatch_delete
    mark_deleted(source: 'chatwoot', sender: 'chatwoot', from_me: true)
    @message
  end

  def apply_incoming
    return if @params.blank?

    @message = @inbox.messages.find_by(source_id: @params[:message_id])
    return if @message.blank?

    mark_deleted(
      source: 'whatsapp',
      sender: incoming_sender,
      from_me: ActiveModel::Type::Boolean.new.cast(@params[:from_me]),
      timestamp: @params[:timestamp]
    )
  end

  private

  def validate_outgoing_delete!
    raise 'Message not found' if @message.blank?
    raise 'Only WhatsApp Direct messages can be deleted for everyone' unless whatsmeow_message?
    raise 'This message cannot be deleted on WhatsApp yet' if @message.source_id.blank?
    raise 'Only outgoing WhatsApp Direct messages can be deleted for everyone' unless @message.outgoing?
  end

  def whatsmeow_message?
    @message.inbox&.channel_type == 'Channel::Whatsmeow'
  end

  def dispatch_delete
    target_identifiers.each_with_index do |identifier, index|
      @target_identifier = identifier
      Whatsmeow::SessionClient.request(:post, '/messages/delete', body: payload)
      return
    rescue Whatsmeow::SessionClient::Error => e
      raise e unless retryable_target_error?(e) && index < target_identifiers.length - 1

      Rails.logger.warn(
        "Whatsmeow: Delete for everyone to #{identifier} failed with #{e.message}; trying another JID..."
      )
    end
  end

  def payload
    {
      channel_id: @message.inbox_id.to_s,
      to: @target_identifier,
      message_id: @message.source_id
    }
  end

  def target_identifiers
    @target_identifiers ||= resolve_target_identifiers
  end

  def resolve_target_identifiers
    return [group_jid].compact_blank if group_message?

    targets = target_candidates.filter_map do |identifier|
      phone_jid(identifier) if phone_identifier?(identifier, source_id)
    end
    targets += target_candidates.select { |identifier| deliverable_jid?(identifier) }
    targets.compact_blank.uniq.presence || missing_target!
  end

  def target_candidates
    additional_attributes = contact&.additional_attributes || {}

    [
      source_id,
      contact&.phone_number,
      additional_attributes['whatsmeow_participant_jid'],
      additional_attributes['whatsmeow_participant_phone'],
      additional_attributes['whatsmeow_participant_lid_jid'],
      contact&.name
    ].compact_blank
  end

  def mark_deleted(source:, sender:, from_me:, timestamp: nil)
    attributes = content_attributes.merge(
      'deleted' => true,
      'whatsmeow_deleted' => source == 'whatsapp' || source == 'chatwoot',
      'whatsmeow_deleted_by' => sender,
      'whatsmeow_deleted_by_name' => @actor&.name,
      'whatsmeow_deleted_from_me' => from_me,
      'whatsmeow_deleted_at' => timestamp.presence || Time.current.to_i
    ).compact

    @message.update!(content_attributes: attributes)
  end

  def content_attributes
    (@message.content_attributes || {}).stringify_keys
  end

  def group_message?
    group_jid.present?
  end

  def group_jid
    @group_jid ||= content_attributes['group_jid'].presence ||
                   contact&.additional_attributes&.dig('whatsmeow_group_jid').presence ||
                   (source_id if group_jid?(source_id))
  end

  def source_id
    @source_id ||= @message.conversation.contact_inbox&.source_id
  end

  def contact
    @contact ||= @message.conversation.contact
  end

  def incoming_sender
    return 'chatwoot' if ActiveModel::Type::Boolean.new.cast(@params[:from_me])

    @params[:sender].presence || @params[:sender_alt].presence || 'whatsapp'
  end

  def phone_identifier?(identifier, source_identifier = nil)
    return false if non_phone_jid?(identifier)

    digits = identifier.to_s.split('@').first.split(':').first.delete('^0-9')
    digits.match?(/\A[1-9]\d{1,14}\z/) && digits != lid_digits(source_identifier)
  end

  def phone_jid(identifier)
    return if identifier.blank?

    "#{identifier.to_s.split('@').first.split(':').first.delete('^0-9')}@s.whatsapp.net"
  end

  def deliverable_jid?(identifier)
    jid = identifier.to_s.downcase
    jid.include?('@') && jid.exclude?('@newsletter')
  end

  def group_jid?(identifier)
    identifier.to_s.downcase.include?('@g.us')
  end

  def non_phone_jid?(identifier)
    jid = identifier.to_s.downcase
    return false unless jid.include?('@')

    jid.exclude?('@s.whatsapp.net')
  end

  def lid_digits(identifier)
    return unless identifier.to_s.downcase.include?('@lid')

    identifier.to_s.split('@').first.split(':').first.delete('^0-9')
  end

  def retryable_target_error?(error)
    error.message.include?('server returned error 403') || error.message.include?('Invalid target')
  end

  def missing_target!
    raise "No deliverable WhatsApp target found for conversation #{@message.conversation_id}"
  end
end
