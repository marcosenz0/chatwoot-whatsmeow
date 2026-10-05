class CreateChannelTelegramPersonal < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_telegram_personal do |t|
      t.references :account, null: false, foreign_key: true
      t.string :phone_number, null: false
      t.string :status, null: false, default: 'disconnected'
      t.string :telegram_user_id
      t.string :username
      t.boolean :ignore_groups, null: false, default: true
      t.boolean :ignore_channels, null: false, default: true
      t.boolean :hide_groups, null: false, default: true
      t.boolean :hide_channels, null: false, default: true
      t.timestamps
    end
    add_index :channel_telegram_personal, [:account_id, :phone_number], unique: true
  end
end
