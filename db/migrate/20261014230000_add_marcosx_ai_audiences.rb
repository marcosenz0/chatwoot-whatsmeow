class AddMarcosxAiAudiences < ActiveRecord::Migration[7.2]
  def change
    create_table :marcosx_ai_notification_targets do |t|
      t.references :account, null: false, foreign_key: true
      t.references :assistant, null: false, foreign_key: { to_table: :marcosx_ai_assistants }
      t.references :inbox, null: false, foreign_key: true
      t.string :title, null: false, default: ''
      t.string :number, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :marcosx_ai_notification_targets, [:assistant_id, :number], unique: true, name: 'marcosx_ai_notification_number'

    %i[marcosx_ai_resources marcosx_ai_pix_keys marcosx_ai_notification_targets].each do |table|
      add_column table, :audience, :string, null: false, default: 'global'
      add_column table, :contact_ids, :jsonb, null: false, default: []
      add_reference table, :conversation, foreign_key: { on_delete: :nullify }
      add_index table, [:assistant_id, :audience], name: "#{table}_audience"
      add_check_constraint table, "audience IN ('global', 'conversation', 'contacts')", name: "#{table}_audience_kind"
    end
  end
end
