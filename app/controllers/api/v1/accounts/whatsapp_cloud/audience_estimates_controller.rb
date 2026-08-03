class Api::V1::Accounts::WhatsappCloud::AudienceEstimatesController < Api::V1::Accounts::WhatsappCloud::BaseController
  def show
    contacts = audience_contacts
    category = params[:category].presence || 'UTILITY'
    estimates = contacts.map { |contact| contact_estimate(contact, category) }
    eligible = estimates.reject { |estimate| estimate[:skipped] }

    render json: {
      total: estimates.length,
      eligible: eligible.length,
      skipped: estimates.length - eligible.length,
      estimated_cost: eligible.sum { |estimate| estimate[:estimated_cost] }.to_d,
      currency: 'BRL',
      category: category.to_s.upcase,
      rate_effective_at: Date.new(2026, 7, 1)
    }
  end

  private

  def audience_contacts
    label_ids = Array(params[:label_ids]).map(&:to_i)
    labels = Current.account.labels.where(id: label_ids).pluck(:title)
    contact_ids = Array(params[:contact_ids]).map(&:to_i)
    contact_ids |= Current.account.contacts.tagged_with(labels, any: true).pluck(:id) if labels.any?

    Current.account.contacts.where(id: contact_ids)
  end

  def contact_estimate(contact, category)
    skipped = contact.phone_number.blank? ||
              contact.blocked? ||
              ActiveModel::Type::Boolean.new.cast(contact.custom_attributes['whatsapp_opt_out']) ||
              contact.label_list.any? { |label| label.to_s.downcase.in?(%w[whatsapp_opt_out do_not_contact optout]) }
    {
      skipped: skipped,
      estimated_cost: estimated_cost(skipped, contact, category)
    }
  end

  def estimated_cost(skipped, contact, category)
    return BigDecimal(0) if skipped

    Whatsapp::PricingService.estimate(category: category, contact: contact, inbox: official_inbox)
  end
end
