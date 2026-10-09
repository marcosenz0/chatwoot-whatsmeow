class CreateMarcosxAiAlerts < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsmeow_calls, :ai_processed_at, :datetime
    create_table :marcosx_ai_alerts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :assistant, null: true, foreign_key: { to_table: :marcosx_ai_assistants, on_delete: :nullify }
      t.string :rule_id, null: false
      t.string :name, null: false
      t.string :action, null: false
      t.string :status, null: false, default: 'open'
      t.text :reason
      t.jsonb :configuration, null: false, default: {}
      t.references :resolved_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :marcosx_ai_alerts, [:conversation_id, :rule_id], unique: true, where: "status = 'open'", name: 'marcosx_ai_open_alert'

    create_table :marcosx_ai_alert_deliveries do |t|
      t.references :alert, null: false, foreign_key: { to_table: :marcosx_ai_alerts, on_delete: :cascade }
      t.string :kind, null: false
      t.string :recipient, null: false
      t.string :status, null: false, default: 'pending'
      t.text :error
      t.integer :attempts, null: false, default: 0
      t.datetime :last_attempt_at
      t.references :message, foreign_key: { on_delete: :nullify }
      t.references :notification, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :marcosx_ai_alert_deliveries, [:alert_id, :kind, :recipient], unique: true, name: 'marcosx_ai_unique_delivery'
  end
end
