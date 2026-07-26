class Whatsapp::PricingService
  DEFAULT_BRAZIL_RATES = {
    'MARKETING' => BigDecimal('0.3217'),
    'UTILITY' => BigDecimal('0.0350'),
    'AUTHENTICATION' => BigDecimal('0.0350')
  }.freeze

  def self.estimate(category:, contact:, inbox:)
    new(category: category, contact: contact, inbox: inbox).estimate
  end

  def initialize(category:, contact:, inbox:)
    @category = category.to_s.upcase
    @contact = contact
    @inbox = inbox
  end

  def estimate
    return BigDecimal(0) if utility_template_is_free_in_open_window?

    configured_rate || DEFAULT_BRAZIL_RATES.fetch(category, BigDecimal(0))
  end

  private

  attr_reader :category, :contact, :inbox

  def configured_rate
    value = ENV.fetch("WHATSAPP_CLOUD_#{category}_RATE_BRL", nil)
    BigDecimal(value) if value.present?
  end

  def utility_template_is_free_in_open_window?
    return false unless category == 'UTILITY'
    return false if Time.current.to_date >= Date.new(2026, 10, 1)

    contact_inbox = contact.contact_inboxes.find_by(inbox_id: inbox.id)
    contact_inbox&.conversations&.last&.can_reply? || false
  end
end
