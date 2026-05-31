class Whatsmeow::ReceiptService
  pattr_initialize [:inbox!, :params!]

  STATUS_PRIORITY = {
    'sent' => 0,
    'delivered' => 1,
    'read' => 2
  }.freeze

  def perform
    return if message_ids.blank?
    return unless STATUS_PRIORITY.key?(status)

    messages.find_each do |message|
      next unless should_update?(message)

      message.update!(status: status)
    end
  end

  private

  def message_ids
    @message_ids ||= Array(params[:message_ids]).compact_blank.uniq
  end

  def status
    @status ||= params[:status].to_s
  end

  def messages
    Message.where(
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      source_id: message_ids,
      message_type: :outgoing
    )
  end

  def should_update?(message)
    return false if message.failed?

    STATUS_PRIORITY.fetch(status) > STATUS_PRIORITY.fetch(message.status, -1)
  end
end
