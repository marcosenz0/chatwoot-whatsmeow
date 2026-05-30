class Whatsmeow::SendOnWhatsmeowService
  pattr_initialize [:message!]

  def perform
    return if message.incoming?
    return if message.private?

    inbox = message.conversation.inbox
    target_jid = message.conversation.contact_inbox.source_id

    payload = {
      channel_id: inbox.id.to_s,
      to: target_jid,
      body: message.content
    }

    Rails.logger.info("Whatsmeow: Sending outgoing message to #{target_jid} on inbox #{inbox.id} via Go API...")

    result = Whatsmeow::SessionClient.request(:post, '/messages', body: payload)
    message.update!(source_id: result['id']) if result['id'].present?
    Rails.logger.info("Whatsmeow: Message dispatched successfully. External ID: #{result['id']}")
  rescue StandardError => e
    Rails.logger.error("Whatsmeow: Exception occurred while sending message: #{e.message}")
  end
end
