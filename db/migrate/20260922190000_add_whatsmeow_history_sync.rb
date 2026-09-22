class AddWhatsmeowHistorySync < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_whatsmeow, :history_sync_days, :integer, default: 90, null: false
    add_column :channel_whatsmeow, :history_sync_auto, :boolean, default: true, null: false
    add_column :channel_whatsmeow, :history_sync_state, :jsonb, default: {}, null: false

    create_table :whatsmeow_history_messages do |t|
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.string :chat_jid, null: false
      t.string :message_id, null: false
      t.datetime :message_at, null: false
      t.binary :payload, null: false
      t.datetime :imported_at
      t.integer :attempts, default: 0, null: false
      t.datetime :retry_at, default: -> { 'CURRENT_TIMESTAMP' }, null: false
      t.datetime :received_at, default: -> { 'CURRENT_TIMESTAMP' }, null: false
      t.index [:inbox_id, :message_id], unique: true, name: 'idx_whatsmeow_history_message'
      t.index [:inbox_id, :imported_at, :retry_at], name: 'idx_whatsmeow_history_pending'
    end

    create_table :whatsmeow_history_chats do |t|
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.string :chat_jid, null: false
      t.string :message_id, null: false
      t.datetime :message_at, null: false
      t.string :sender_jid, default: '', null: false
      t.boolean :from_me, default: false, null: false
      t.string :requested_id
      t.datetime :requested_at
      t.index [:inbox_id, :chat_jid], unique: true, name: 'idx_whatsmeow_history_chat'
    end
  end
end
