class Channel::Whatsmeow < ApplicationRecord
  include Channelable

  self.table_name = 'channel_whatsmeow'
  EDITABLE_ATTRS = [:phone_number].freeze

  validates :phone_number, presence: true

  def name
    'Whatsmeow'
  end

  def has_failed_delivery?
    false
  end
end
