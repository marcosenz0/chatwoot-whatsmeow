class AddIgnoreNewslettersToChannelWhatsmeow < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_whatsmeow, :ignore_newsletters, :boolean, default: true, null: false
  end
end
