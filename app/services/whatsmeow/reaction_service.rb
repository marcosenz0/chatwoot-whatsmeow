class Whatsmeow::ReactionService
  def self.apply_incoming(inbox:, params:)
    new(inbox: inbox, params: params).apply_incoming
  end

  def initialize(message: nil, emoji: nil, actor: nil, inbox: nil, params: nil)
    @message = message
    @emoji = emoji
    @actor = actor
    @inbox = inbox
    @params = params&.with_indifferent_access
  end

  def perform
    validate_outgoing_reaction!

    dispatch_reaction
    persist_reaction(
      emoji: normalized_emoji,
      sender: 'chatwoot',
      sender_name: @actor&.name,
      from_me: true,
      source: 'chatwoot'
    )
    @message
  end

  def apply_incoming
    return if @params.blank?

    @message = @inbox.messages.find_by(source_id: @params[:message_id])
    return if @message.blank?

    persist_reaction(
      emoji: @params[:reaction],
      sender: incoming_sender,
      sender_name: nil,
      from_me: ActiveModel::Type::Boolean.new.cast(@params[:from_me]),
      source: 'whatsapp',
      timestamp: @params[:timestamp]
    )
  end

  private

  def validate_outgoing_reaction!
    raise 'Message not found' if @message.blank?
    raise 'Only WhatsApp Direct messages support reactions' unless whatsmeow_message?
    raise 'This message cannot be reacted to yet' if @message.source_id.blank?
  end

  def whatsmeow_message?
    @message.inbox&.channel_type == 'Channel::Whatsmeow'
  end

  def dispatch_reaction
    target_identifiers.each_with_index do |identifier, index|
      @target_identifier = identifier
      Whatsmeow::SessionClient.request(:post, '/messages/reaction', body: payload)
      return
    rescue Whatsmeow::SessionClient::Error => e
      raise e unless retryable_target_error?(e) && index < target_identifiers.length - 1

      Rails.logger.warn(
        "Whatsmeow: Reaction to #{identifier} failed with #{e.message}; trying another JID..."
      )
    end
  end

  def payload
    {
      channel_id: @message.inbox_id.to_s,
      to: @target_identifier,
      sender: target_message_sender,
      message_id: @message.source_id
    }.compact_blank.merge(
      emoji: normalized_emoji
    )
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

  def target_message_sender
    return if @message.outgoing?

    identifier = sender_candidates.find do |candidate|
      deliverable_jid?(candidate) || phone_identifier?(candidate)
    end
    return phone_jid(identifier) if phone_identifier?(identifier)

    identifier
  end

  def sender_candidates
    if group_message?
      [
        content_attributes['participant_jid'],
        content_attributes['participant_lid_jid'],
        phone_jid(content_attributes['participant_phone']),
        @message.sender&.phone_number,
        @message.sender&.additional_attributes&.dig('whatsmeow_participant_jid'),
        @message.sender&.additional_attributes&.dig('whatsmeow_participant_lid_jid')
      ].compact_blank
    else
      target_candidates
    end
  end

  def persist_reaction(emoji:, sender:, sender_name:, from_me:, source:, timestamp: nil)
    emoji = emoji.to_s.strip
    return remove_reaction(sender) if emoji.blank?

    reaction = {
      'emoji' => emoji,
      'sender' => sender,
      'sender_name' => sender_name,
      'from_me' => from_me,
      'source' => source,
      'created_at' => timestamp.presence || Time.current.to_i
    }.compact

    attributes = content_attributes.merge(
      'whatsmeow_reactions' => upserted_reactions(reaction),
      'whatsmeow_reaction' => reaction
    )
    @message.update!(content_attributes: attributes)
  end

  def upserted_reactions(reaction)
    reaction_sender = reaction['sender'].to_s
    existing = normalized_reactions.reject do |item|
      item['sender'].to_s == reaction_sender
    end

    existing << reaction
  end

  def remove_reaction(sender)
    reactions = normalized_reactions.reject do |item|
      item['sender'].to_s == sender.to_s
    end
    attributes = content_attributes.merge('whatsmeow_reactions' => reactions)

    if reactions.present?
      attributes['whatsmeow_reaction'] = reactions.last
    else
      attributes.delete('whatsmeow_reaction')
      attributes.delete('whatsmeow_reactions')
    end

    @message.update!(content_attributes: attributes)
  end

  def normalized_reactions
    Array(content_attributes['whatsmeow_reactions']).filter_map do |item|
      next item.with_indifferent_access.to_h if item.respond_to?(:with_indifferent_access)
      next { 'emoji' => item } if item.is_a?(String)
    end
  end

  def content_attributes
    @content_attributes ||= (@message.content_attributes || {}).stringify_keys
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

  def normalized_emoji
    @normalized_emoji ||= @emoji.to_s.strip
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
