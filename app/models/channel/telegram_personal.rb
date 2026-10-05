class Channel::TelegramPersonal < ApplicationRecord
  include Channelable

  self.table_name = 'channel_telegram_personal'
  EDITABLE_ATTRS = [:phone_number, :ignore_groups, :ignore_channels, :hide_groups, :hide_channels].freeze

  validates :phone_number, presence: true, format: { with: /\A\+[1-9]\d{7,14}\z/ }, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: %w[disconnected connecting qr password connected error] }
  validate :phone_cannot_change_when_connected
  before_destroy :disconnect_session
  after_update_commit :sync_session_settings, if: -> { saved_change_to_ignore_groups? || saved_change_to_ignore_channels? }

  def name = 'TelegramPersonal'

  private

  def sync_session_settings
    return if ENV['TELEGRAM_PERSONAL_SERVICE_URL'].blank?

    TelegramPersonal::SessionClient.new(inbox: inbox).settings(ignore_groups: ignore_groups, ignore_channels: ignore_channels)
  end

  def phone_cannot_change_when_connected
    return unless phone_number_changed? && status == 'connected'

    errors.add(:phone_number, 'Disconnect the Telegram account before changing the number')
  end

  def disconnect_session
    TelegramPersonal::SessionClient.new(inbox: inbox).disconnect if inbox && ENV['TELEGRAM_PERSONAL_SERVICE_URL'].present?
  end
end
