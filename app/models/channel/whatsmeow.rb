class Channel::Whatsmeow < ApplicationRecord
  include Channelable

  self.table_name = 'channel_whatsmeow'
  EDITABLE_ATTRS = [
    :phone_number,
    :status,
    :newsletter,
    :always_online,
    :reject_calls,
    :read_messages,
    :ignore_groups,
    :ignore_status,
    :hide_status_views,
    :ignore_newsletters,
    :typing_enabled,
    :history_sync_days,
    :history_sync_auto
  ].freeze

  validates :history_sync_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 3650 }
  validate :valid_pix_configuration

  encrypts :pix_key if Chatwoot.encryption_configured?

  def name
    'Whatsmeow'
  end

  def pix_configured?
    pix_key_type.present? && pix_key.present? && pix_merchant_name.present?
  end

  private

  def valid_pix_configuration
    values = [pix_key_type, pix_key, pix_merchant_name]
    return if values.all?(&:blank?)

    payload = Whatsmeow::PixPayload.new(key_type: pix_key_type, key: pix_key, merchant_name: pix_merchant_name)
    return if payload.valid?

    payload.errors.each do |error|
      errors.add("pix_#{error.attribute}", error.message)
    end
  end
end
