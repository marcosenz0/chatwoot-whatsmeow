class CreateWhatsmeowStatuses < ActiveRecord::Migration[7.0]
  def change
    create_statuses
    create_status_views
  end

  private

  def create_statuses
    create_table :whatsmeow_statuses do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :contact, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :source_id, null: false
      t.string :sender_jid, null: false
      t.string :sender_name
      t.string :sender_phone
      t.integer :status_type, null: false, default: 0
      t.text :content
      t.boolean :from_me, null: false, default: false
      t.datetime :posted_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :read_receipt_sent_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_status_indexes
  end

  def add_status_indexes
    add_index :whatsmeow_statuses, [:inbox_id, :source_id], unique: true
    add_index :whatsmeow_statuses, [:inbox_id, :expires_at]
    add_index :whatsmeow_statuses, :expires_at
    add_index :whatsmeow_statuses, [:inbox_id, :sender_jid, :posted_at], name: 'idx_whatsmeow_statuses_on_inbox_sender_posted'
  end

  def create_status_views
    create_table :whatsmeow_status_views do |t|
      t.references :whatsmeow_status, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :viewed_at, null: false

      t.timestamps
    end

    add_index :whatsmeow_status_views, [:whatsmeow_status_id, :user_id], unique: true, name: 'idx_whatsmeow_status_views_on_status_user'
  end
end
