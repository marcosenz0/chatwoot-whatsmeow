class Whatsapp::OneoffCampaignService
  pattr_initialize [:campaign!]

  def perform
    validate_campaign!
    deliveries = campaign.with_lock do
      raise 'Campaign is no longer active' unless campaign.active?

      campaign.processing!
      build_deliveries
    end

    if deliveries.empty?
      campaign.failed!
      return
    end

    deliveries.each do |delivery|
      next if delivery.skipped?

      Whatsapp::ProcessCampaignDeliveryJob.perform_later(delivery.id)
    end
    campaign.complete_whatsapp_campaign_if_finished!
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def validate_campaign!
    raise "Invalid campaign #{campaign.id}" unless campaign.one_off? && inbox.inbox_type == 'Whatsapp'
    raise 'WhatsApp Cloud provider required' unless channel.provider == 'whatsapp_cloud'

    consent_confirmed = ActiveModel::Type::Boolean.new.cast(campaign.trigger_rules['whatsapp_consent_confirmed'])
    raise 'Campaign audience consent must be confirmed' unless consent_confirmed
    raise 'Template parameters are required' if campaign.template_params.blank?

    validate_linked_automation!
  end

  def validate_linked_automation!
    automation_id = campaign.trigger_rules['whatsapp_automation_id']
    return if automation_id.blank?

    automation = campaign.account.whatsapp_automations.enabled.find_by(
      id: automation_id,
      inbox_id: inbox.id,
      trigger_type: 'campaign_reply'
    )
    raise 'Linked WhatsApp flow is unavailable' if automation.blank?
    raise 'Linked WhatsApp flow uses another template' if automation.trigger_config['template_name'] != campaign.template_params['name']
  end

  def build_deliveries
    audience_contacts.filter_map do |contact|
      attributes = delivery_attributes(contact)
      campaign.whatsapp_campaign_deliveries.create_with(attributes).find_or_create_by!(
        account: campaign.account,
        contact: contact
      )
    end
  end

  def audience_contacts
    labels = campaign.account.labels.where(id: audience_label_ids).pluck(:title)
    contact_ids = audience_contact_ids
    contact_ids |= campaign.account.contacts.tagged_with(labels, any: true).pluck(:id) if labels.any?

    campaign.account.contacts.where(id: contact_ids)
  end

  def audience_label_ids
    campaign.audience.select { |audience| audience['type'] == 'Label' }.pluck('id')
  end

  def audience_contact_ids
    campaign.audience.select { |audience| audience['type'] == 'Contact' }.pluck('id')
  end

  def delivery_attributes(contact)
    category = campaign.template_params['category'].presence || 'UTILITY'
    skipped_reason = skip_reason(contact)
    {
      status: skipped_reason.present? ? :skipped : :queued,
      phone_number: contact.phone_number,
      template_category: category,
      estimated_cost: estimated_cost(contact, category, skipped_reason),
      error_message: skipped_reason
    }
  end

  def estimated_cost(contact, category, skipped_reason)
    return 0 if skipped_reason.present?

    Whatsapp::PricingService.estimate(category: category, contact: contact, inbox: inbox)
  end

  def skip_reason(contact)
    return 'Contact has no phone number' if contact.phone_number.blank?
    return 'Contact is blocked' if contact.blocked?
    return 'Contact opted out of WhatsApp messages' if whatsapp_opted_out?(contact)
  end

  def whatsapp_opted_out?(contact)
    ActiveModel::Type::Boolean.new.cast(contact.custom_attributes['whatsapp_opt_out']) ||
      contact.label_list.any? { |label| label.to_s.downcase.in?(%w[whatsapp_opt_out do_not_contact optout]) }
  end
end
