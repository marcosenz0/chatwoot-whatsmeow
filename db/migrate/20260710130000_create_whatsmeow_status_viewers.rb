class CreateWhatsmeowStatusViewers < ActiveRecord::Migration[7.0]
  def change
    create_table :whatsmeow_status_viewers do |t|
      t.references :whatsmeow_status, null: false, foreign_key: true
      t.references :contact, foreign_key: { on_delete: :nullify }
      t.string :viewer_jid, null: false
      t.string :viewer_name
      t.string :viewer_phone
      t.datetime :viewed_at, null: false

      t.timestamps
    end

    add_index :whatsmeow_status_viewers, [:whatsmeow_status_id, :viewer_jid],
              unique: true,
              name: 'idx_whatsmeow_status_viewers_on_status_viewer'
    add_index :whatsmeow_status_viewers, :viewed_at
  end
end
