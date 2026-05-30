class Whatsmeow::SendOnWhatsmeowService
  pattr_initialize [:message!]

  def perform
    return if message.incoming?
    return if message.private?

    inbox = message.conversation.inbox
    target_jid = message.conversation.contact_inbox.source_id

    # The Whatsmeow service URL
    service_url = ENV.fetch('WHATSMEOW_SERVICE_URL', 'http://whatsmeow-staging:8080')
    url = "#{service_url}/messages"

    payload = {
      channel_id: inbox.id.to_s,
      to: target_jid,
      body: message.content
    }

    Rails.logger.info("Whatsmeow: Sending outgoing message to #{target_jid} on inbox #{inbox.id} via Go API...")

    response = HTTParty.post(
      url,
      body: payload.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 10
    )

    if response.success?
      result = JSON.parse(response.body)
      message.update!(source_id: result['id']) if result['id'].present?
      Rails.logger.info("Whatsmeow: Message dispatched successfully. External ID: #{result['id']}")
    else
      Rails.logger.error("Whatsmeow: Failed to send message via Go API. Response: #{response.body}")
    end
  rescue StandardError => e
    Rails.logger.error("Whatsmeow: Exception occurred while sending message: #{e.message}")
  end
end
