class WhatsappAutomationListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    Whatsapp::Automation::InboundMessageService.new(message: message).perform
    sync_campaign_delivery(message)
  end

  def message_updated(event)
    message = event.data[:message]
    sync_campaign_delivery(message)
    resume_automation_run(message)
  end

  private

  def resume_automation_run(message)
    return unless official_whatsapp_cloud_message?(message)
    return unless message.failed? || message.source_id.present? || message.delivered? || message.read?

    WhatsappAutomationRun.unfinished
                         .where(account_id: message.account_id, conversation_id: message.conversation_id)
                         .where("context ->> 'awaiting_message_id' = ?", message.id.to_s)
                         .find_each do |run|
      Whatsapp::Automation::RunJob.perform_later(run.id)
    end
  end

  def official_whatsapp_cloud_message?(message)
    message.outgoing? &&
      message.inbox.channel_type == 'Channel::Whatsapp' &&
      message.inbox.channel.provider == 'whatsapp_cloud'
  end

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
