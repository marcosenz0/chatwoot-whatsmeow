class AddTypingEnabledToChannelWhatsmeow < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_whatsmeow, :typing_enabled, :boolean, default: true, null: false
  end
end
