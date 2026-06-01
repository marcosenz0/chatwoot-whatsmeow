class AllowNullWhatsmeowPhoneNumber < ActiveRecord::Migration[7.0]
  def change
    change_column_null :channel_whatsmeow, :phone_number, true
  end
end
