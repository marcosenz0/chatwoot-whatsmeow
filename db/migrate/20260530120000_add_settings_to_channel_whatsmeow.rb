class AddSettingsToChannelWhatsmeow < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_whatsmeow, :status, :string, default: 'disconnected'
    add_column :channel_whatsmeow, :newsletter, :boolean, default: false, null: false
    add_column :channel_whatsmeow, :always_online, :boolean, default: false, null: false
    add_column :channel_whatsmeow, :reject_calls, :boolean, default: false, null: false
    add_column :channel_whatsmeow, :read_messages, :boolean, default: false, null: false
    add_column :channel_whatsmeow, :ignore_groups, :boolean, default: false, null: false
    add_column :channel_whatsmeow, :ignore_status, :boolean, default: false, null: false
  end
end
