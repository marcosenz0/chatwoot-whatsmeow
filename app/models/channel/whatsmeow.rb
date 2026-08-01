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
    :ignore_newsletters
  ].freeze

  def name
    'Whatsmeow'
  end
end
