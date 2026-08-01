class Whatsapp::CloudMessageStatusService
  class MessageNotFoundError < StandardError; end

  STATUS_RANK = {
    'sent' => 0,
    'delivered' => 1,
    'read' => 2
  }.freeze

  pattr_initialize [:message!, :status!]

  def perform
    normalized_status = status.with_indifferent_access
    status_applied = status_should_apply?(normalized_status)
    message.status = normalized_status[:status] if status_applied
    merge_status_metadata(normalized_status)
    assign_failure(normalized_status) if status_applied
    message.save!
  end

  private

  def status_should_apply?(normalized_status)
    incoming_status = normalized_status[:status].to_s
    current_status = message.status.to_s
    return repeated_failure_is_current?(normalized_status) if message.failed?
    return false if incoming_status == 'failed' && current_status.in?(%w[delivered read])
    return failure_is_current?(normalized_status) if incoming_status == 'failed'
    return false unless STATUS_RANK.key?(incoming_status)

    STATUS_RANK.fetch(incoming_status) >= STATUS_RANK.fetch(current_status, -1)
  end

  def repeated_failure_is_current?(normalized_status)
    return false unless normalized_status[:status].to_s == 'failed'

    incoming_timestamp = whatsapp_status_timestamp(normalized_status[:timestamp])
    current_timestamp = message.content_attributes.dig('whatsapp_status_timestamps', 'failed')
    return true if current_timestamp.blank?
    return false if incoming_timestamp.blank?

    incoming_timestamp >= current_timestamp.to_i
  end

  def failure_is_current?(normalized_status)
    incoming_timestamp = whatsapp_status_timestamp(normalized_status[:timestamp])
    current_timestamp = message.content_attributes.dig('whatsapp_status_timestamps', message.status)
    return true if incoming_timestamp.blank? || current_timestamp.blank?

    incoming_timestamp >= current_timestamp.to_i
  end

  def merge_status_metadata(normalized_status)
    content_attributes = message.content_attributes.deep_dup
    content_attributes['whatsapp_pricing'] = normalized_status[:pricing].to_h.stringify_keys if normalized_status[:pricing].present?

    timestamp = whatsapp_status_timestamp(normalized_status[:timestamp])
    if timestamp.present?
      timestamps = content_attributes.fetch('whatsapp_status_timestamps', {}).stringify_keys
      status_name = normalized_status[:status].to_s
      timestamps[status_name] = [timestamps[status_name].to_i, timestamp].max
      content_attributes['whatsapp_status_timestamps'] = timestamps
    end

    message.content_attributes = content_attributes
  end

  def assign_failure(normalized_status)
    return unless normalized_status[:status] == 'failed' && normalized_status[:errors].present?

    error = normalized_status[:errors].first
    message.external_error = "#{error[:code]}: #{error[:title]}"
  end

  def whatsapp_status_timestamp(value)
    timestamp = Integer(value, exception: false)
    timestamp if timestamp&.positive?
  end
end
