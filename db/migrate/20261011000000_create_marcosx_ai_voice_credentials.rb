class CreateMarcosxAiVoiceCredentials < ActiveRecord::Migration[7.2]
  def change
    create_table :marcosx_ai_voice_credentials do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :assistant, null: false, foreign_key: { to_table: :marcosx_ai_assistants, on_delete: :cascade }
      t.string :provider, null: false
      t.text :api_key
      t.timestamps
    end
    add_index :marcosx_ai_voice_credentials, [:assistant_id, :provider], unique: true
  end
end
