class WhatsappAutomationListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    Whatsapp::Automation::InboundMessageService.new(message: message).perform
    sync_campaign_delivery(message)
  end

  def message_updated(event)
    sync_campaign_delivery(event.data[:message])
  end

  private

  def sync_campaign_delivery(message)
    delivery = WhatsappCampaignDelivery.find_by(message_id: message.id)
    if delivery.blank? && message.additional_attributes['campaign_id'].present?
      delivery = WhatsappCampaignDelivery.find_by(
        campaign_id: message.additional_attributes['campaign_id'],
        contact_id: message.conversation.contact_id
      )
      delivery&.update!(message: message)
    end
    delivery&.sync_from_message!
  end
end
