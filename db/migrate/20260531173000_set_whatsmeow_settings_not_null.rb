class SetWhatsmeowSettingsNotNull < ActiveRecord::Migration[7.0]
  SETTINGS = %i[
    newsletter
    always_online
    reject_calls
    read_messages
    ignore_groups
    ignore_status
  ].freeze

  def change
    SETTINGS.each do |column|
      change_column_null :channel_whatsmeow, column, false, false
    end
  end
end
