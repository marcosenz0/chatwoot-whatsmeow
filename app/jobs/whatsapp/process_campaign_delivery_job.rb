class Whatsapp::ProcessCampaignDeliveryJob < ApplicationJob
  queue_as :low

  def perform(delivery_id)
    delivery = WhatsappCampaignDelivery.find_by(id: delivery_id)
    return unless processable?(delivery)
    return unless claim_delivery(delivery)

    message = build_message(delivery)
    associate_message(delivery, message)
    delivery.sync_from_message!
  rescue StandardError => e
    handle_failure(delivery, e)
  end

  private

  def processable?(delivery)
    delivery.present? && !delivery.skipped? && !delivery.read? && !delivery.delivered?
  end

  def claim_delivery(delivery)
    claimed = false
    delivery.with_lock do
      if delivery.queued? || delivery.failed?
        delivery.update!(status: :processing, error_message: nil, failed_at: nil)
        claimed = true
      end
    end
    claimed
  end

  def associate_message(delivery, message)
    delivery.update!(message: message)
  end

  def handle_failure(delivery, error)
    delivery&.update!(status: :failed, error_message: error.message, failed_at: Time.current)
    delivery&.campaign&.complete_whatsapp_campaign_if_finished!
    ChatwootExceptionTracker.new(error, account: delivery&.account).capture_exception
  end

  def build_message(delivery)
    campaign = delivery.campaign
    contact = delivery.contact
    conversation = campaign_conversation(campaign, contact)
    template_params = processed_template_params(campaign, contact)
    Messages::MessageBuilder.new(campaign.sender, conversation, message_params(campaign, delivery, template_params)).perform
  end

  def campaign_conversation(campaign, contact)
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: campaign.inbox).perform
    contact_inbox.conversations.where.not(status: :resolved).last ||
      contact_inbox.conversations.last ||
      Conversation.create!(
        account: campaign.account,
        inbox: campaign.inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        campaign: campaign
      )
  end

  def processed_template_params(campaign, contact)
    params = Whatsapp::LiquidTemplateProcessorService.new(
      campaign: campaign,
      contact: contact
    ).process_template_params(campaign.template_params)
    raise 'Template variables resolved to blank values' if params.blank?

    params
  end

  def message_params(campaign, delivery, template_params)
    ActionController::Parameters.new(
      content: campaign.message,
      private: false,
      campaign_id: campaign.id,
      template_params: template_params,
      content_attributes: { whatsapp_campaign_delivery_id: delivery.id }
    )
  end
end
