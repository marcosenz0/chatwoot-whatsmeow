class AddPublicationTrackingToWhatsmeowStatuses < ActiveRecord::Migration[7.1]
  def change
    change_table :whatsmeow_statuses, bulk: true do |t|
      t.string :publication_id
      t.string :session_key
      t.integer :publication_position
      t.integer :publication_state, default: 2, null: false
      t.integer :publish_attempts, default: 0, null: false
      t.text :last_error
      t.datetime :next_attempt_at
    end

    add_index :whatsmeow_statuses, [:account_id, :publication_id, :publication_position],
              name: 'idx_whatsmeow_statuses_on_publication'
    add_index :whatsmeow_statuses, [:publication_id, :inbox_id],
              unique: true,
              where: 'publication_id IS NOT NULL',
              name: 'idx_whatsmeow_statuses_on_publication_inbox'
    add_index :whatsmeow_statuses, [:publication_state, :next_attempt_at],
              name: 'idx_whatsmeow_statuses_on_publish_state'
  end
end
