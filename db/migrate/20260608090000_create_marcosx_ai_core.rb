class CreateMarcosxAiCore < ActiveRecord::Migration[7.0]
  def change
    create_table :marcosx_ai_assistants do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.text :instructions
      t.jsonb :config, null: false, default: {}
      t.jsonb :response_guidelines, null: false, default: []
      t.jsonb :guardrails, null: false, default: []

      t.timestamps
    end

    create_table :marcosx_ai_credentials do |t|
      t.references :account, null: false, foreign_key: true
      t.string :provider, null: false
      t.text :api_key
      t.string :api_base
      t.string :model
      t.boolean :enabled, null: false, default: false

      t.timestamps
    end
    add_index :marcosx_ai_credentials, [:account_id, :provider], unique: true

    create_table :marcosx_ai_inboxes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :assistant, null: false, foreign_key: { to_table: :marcosx_ai_assistants }
      t.references :inbox, null: false, foreign_key: true

      t.timestamps
    end
    add_index :marcosx_ai_inboxes, [:assistant_id, :inbox_id], unique: true
    add_index :marcosx_ai_inboxes, :inbox_id, unique: true

    create_table :marcosx_ai_conversation_states do |t|
      t.references :account, null: false, foreign_key: true
      t.references :assistant, foreign_key: { to_table: :marcosx_ai_assistants }
      t.references :conversation, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.string :status, null: false, default: 'active'
      t.datetime :paused_until
      t.bigint :last_human_message_id
      t.bigint :last_ai_message_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :marcosx_ai_conversation_states, :conversation_id, unique: true, name: 'index_marcosx_ai_states_on_conversation_id'
    add_index :marcosx_ai_conversation_states, [:account_id, :status]

    create_table :marcosx_ai_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :assistant, foreign_key: { to_table: :marcosx_ai_assistants }
      t.references :conversation, foreign_key: true
      t.string :event, null: false
      t.string :status, null: false, default: 'ok'
      t.jsonb :request, null: false, default: {}
      t.jsonb :response, null: false, default: {}
      t.text :error

      t.timestamps
    end
    add_index :marcosx_ai_logs, [:account_id, :created_at]

    create_table :marcosx_ai_google_connections do |t|
      t.references :account, null: false, foreign_key: true
      t.string :email
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at
      t.jsonb :scopes, null: false, default: []
      t.string :status, null: false, default: 'disconnected'

      t.timestamps
    end
    add_index :marcosx_ai_google_connections, :account_id, unique: true
  end
end
