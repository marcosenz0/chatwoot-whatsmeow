class CreateMarcosxAiWorkspace < ActiveRecord::Migration[7.2]
  def change
    create_table :marcosx_ai_test_sessions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :assistant, null: false, foreign_key: { to_table: :marcosx_ai_assistants, on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :title, null: false, default: ''
      t.jsonb :messages, null: false, default: []
      t.datetime :processing_started_at
      t.string :turn_token
      t.text :last_error
      t.timestamps
    end
    add_index :marcosx_ai_test_sessions, [:account_id, :assistant_id, :user_id, :updated_at], name: 'idx_marcosx_ai_test_sessions_owner'

    create_table :marcosx_ai_contact_memories do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :forgotten_at
      t.bigint :cutoff_message_id
      t.jsonb :excluded_message_ids, null: false, default: []
      t.timestamps
    end
    add_index :marcosx_ai_contact_memories, [:account_id, :contact_id], unique: true, name: 'idx_marcosx_ai_contact_memory'
  end
end
