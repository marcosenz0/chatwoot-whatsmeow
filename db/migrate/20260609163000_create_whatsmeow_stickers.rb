class CreateWhatsmeowStickers < ActiveRecord::Migration[7.0]
  def change
    create_table :whatsmeow_stickers do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :attachment, null: false, foreign_key: true
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :whatsmeow_stickers, [:account_id, :user_id, :attachment_id], unique: true, name: 'idx_whatsmeow_stickers_on_account_user_attachment'
  end
end
