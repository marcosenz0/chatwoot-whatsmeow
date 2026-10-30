class AddMarcosxAiConnectionFallbacks < ActiveRecord::Migration[7.2]
  def up
    add_column :marcosx_ai_credentials, :name, :string, null: false, default: 'Principal'
    add_column :marcosx_ai_credentials, :health, :jsonb, null: false, default: {}
    add_column :marcosx_ai_assistants, :connection_status, :jsonb, null: false, default: {}
    remove_index :marcosx_ai_credentials, name: 'index_marcosx_ai_credentials_on_account_id_and_provider'
    add_index :marcosx_ai_credentials, [:account_id, :provider, :name], unique: true, name: 'index_marcosx_ai_credentials_named_connections'
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Preserve named connections and their keys'
  end
end
