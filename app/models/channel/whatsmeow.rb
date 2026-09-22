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

  def name
    'Whatsmeow'
  end
end
