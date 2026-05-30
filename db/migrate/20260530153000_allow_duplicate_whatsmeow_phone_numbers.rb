class AllowDuplicateWhatsmeowPhoneNumbers < ActiveRecord::Migration[7.0]
  def up
    if index_exists?(:channel_whatsmeow, :phone_number, name: :index_channel_whatsmeow_on_phone_number)
      remove_index :channel_whatsmeow, name: :index_channel_whatsmeow_on_phone_number
    end

    return if index_exists?(:channel_whatsmeow, :phone_number, name: :index_channel_whatsmeow_on_phone_number)

    add_index :channel_whatsmeow, :phone_number, name: :index_channel_whatsmeow_on_phone_number
  end

  def down
    if index_exists?(:channel_whatsmeow, :phone_number, name: :index_channel_whatsmeow_on_phone_number)
      remove_index :channel_whatsmeow, name: :index_channel_whatsmeow_on_phone_number
    end

    add_index :channel_whatsmeow, :phone_number, unique: true, name: :index_channel_whatsmeow_on_phone_number
  end
end
