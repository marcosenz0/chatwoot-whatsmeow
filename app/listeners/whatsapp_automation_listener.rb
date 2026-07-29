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

    return fail_automation_runs(message) if message.failed?

    automation_runs_for_message(message, unfinished: true).find_each do |run|
      Whatsapp::Automation::RunJob.perform_later(run.id)
    end
  end

  def fail_automation_runs(message)
    automation_runs_for_message(message, unfinished: false).find_each do |run|
      run.with_lock do
        next if run.failed? || run.cancelled?

        run.update!(
          status: :failed,
          next_run_at: nil,
          last_error: message.external_error.presence || "WhatsApp message #{message.id} failed"
        )
      end
    end
  end

  def automation_runs_for_message(message, unfinished:)
    relation = WhatsappAutomationRun.where(
      account_id: message.account_id,
      conversation_id: message.conversation_id
    )
    relation = relation.unfinished if unfinished

    run_id = message.content_attributes&.dig('whatsapp_automation_run_id')
    return relation.where(id: run_id) if run_id.present?

    relation.where(
      "context ->> 'awaiting_message_id' = :message_id OR context ->> 'last_outgoing_message_id' = :message_id",
      message_id: message.id.to_s
    )
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
