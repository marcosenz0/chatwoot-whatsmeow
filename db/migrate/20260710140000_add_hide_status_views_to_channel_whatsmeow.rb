class AddHideStatusViewsToChannelWhatsmeow < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_whatsmeow, :hide_status_views, :boolean, default: false, null: false
  end
end
