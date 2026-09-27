class AddPixConfigurationToChannelWhatsmeow < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_whatsmeow, :pix_key_type, :string
    add_column :channel_whatsmeow, :pix_key, :text
    add_column :channel_whatsmeow, :pix_merchant_name, :string
  end
end
