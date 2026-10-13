class CreateMarcosxAiResources < ActiveRecord::Migration[7.2]
  def change
    create_table :marcosx_ai_resources do |t|
      t.references :account, null: false, foreign_key: true
      t.references :assistant, null: false, foreign_key: { to_table: :marcosx_ai_assistants }
      t.string :title, null: false
      t.text :description, null: false
      t.string :kind, null: false
      t.text :url
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :marcosx_ai_resources, [:assistant_id, :enabled]
  end
end
