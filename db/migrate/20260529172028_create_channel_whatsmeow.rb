class CreateChannelWhatsmeow < ActiveRecord::Migration[7.0]
  def change
    create_table :channel_whatsmeow do |t|
      t.string :phone_number, null: false
      t.integer :account_id, null: false
      t.timestamps
    end

    add_index :channel_whatsmeow, :phone_number, unique: true
  end
end
