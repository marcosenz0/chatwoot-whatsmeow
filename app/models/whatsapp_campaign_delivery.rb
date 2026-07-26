class WhatsappCampaignDelivery < ApplicationRecord
  belongs_to :account
  belongs_to :campaign
  belongs_to :contact
  belongs_to :message, optional: true

  enum status: {
    queued: 0,
    processing: 1,
    sent: 2,
    delivered: 3,
    read: 4,
    failed: 5,
    skipped: 6
  }

  validates :phone_number, presence: true, unless: :skipped?
  validates :contact_id, uniqueness: { scope: :campaign_id }
  validate :associations_belong_to_account

  scope :terminal, -> { where(status: [:sent, :read, :delivered, :failed, :skipped]) }

  def sync_from_message!
    return if message.blank?

    attributes = {
      source_id: message.source_id.presence || source_id,
      error_message: message.external_error.presence || error_message
    }
    attributes.merge!(message_status_attributes)
    attributes.merge!(message_pricing_attributes)
    update!(attributes.compact)
    campaign.complete_whatsapp_campaign_if_finished!
  end

  private

  def message_status_attributes
    case message.status
    when 'read' then { status: :read, read_at: Time.current }
    when 'delivered' then { status: :delivered, delivered_at: Time.current }
    when 'failed' then { status: :failed, failed_at: Time.current }
    when 'sent' then { status: :sent, sent_at: sent_at || Time.current }
    else {}
    end
  end

  def message_pricing_attributes
    pricing = message.content_attributes&.dig('whatsapp_pricing') || {}
    {
      billable: pricing['billable'],
      pricing_model: pricing['pricing_model'],
      template_category: pricing['category'].presence || template_category
    }
  end

  def associations_belong_to_account
    return if campaign.blank? || contact.blank?

    errors.add(:campaign, 'must belong to the same account') if campaign.account_id != account_id
    errors.add(:contact, 'must belong to the same account') if contact.account_id != account_id
  end
end
