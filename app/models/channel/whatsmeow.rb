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
    :ignore_newsletters
  ].freeze

  validates :phone_number, presence: true

  def name
    'Whatsmeow'
  end
end
