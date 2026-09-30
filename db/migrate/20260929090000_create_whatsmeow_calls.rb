class CreateWhatsmeowCalls < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsmeow_calls do |t|
      t.references :account, :inbox, null: false, foreign_key: true
      t.references :contact, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :agent, foreign_key: { to_table: :users }
      t.string :source_id, null: false
      t.string :peer_jid, null: false
      t.string :direction, null: false
      t.string :status, null: false, default: 'ringing'
      t.boolean :video, null: false, default: false
      t.datetime :started_at, null: false
      t.datetime :connected_at
      t.datetime :ended_at
      t.string :end_reason

      t.timestamps
    end

    add_index :whatsmeow_calls, [:inbox_id, :source_id], unique: true
    add_index :whatsmeow_calls, [:account_id, :started_at]
    add_index :whatsmeow_calls, [:inbox_id, :peer_jid, :started_at]
  end
end
