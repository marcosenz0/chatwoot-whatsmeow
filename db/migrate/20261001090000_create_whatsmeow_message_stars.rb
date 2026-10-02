class CreateWhatsmeowMessageStars < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsmeow_message_stars do |t|
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.references :message, foreign_key: { on_delete: :nullify }
      t.string :chat_jid, null: false
      t.string :source_id, null: false
      t.boolean :starred, null: false, default: true
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :whatsmeow_message_stars, [:inbox_id, :chat_jid, :source_id], unique: true, name: 'index_whatsmeow_stars_on_target'
    add_index :whatsmeow_message_stars, [:inbox_id, :starred, :occurred_at], name: 'index_whatsmeow_stars_on_feed'
  end
end
