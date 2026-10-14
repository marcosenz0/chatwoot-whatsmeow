class CreateMarcosxAiPixKeys < ActiveRecord::Migration[7.2]
  def change
    create_table :marcosx_ai_pix_keys do |t|
      t.references :account, null: false, foreign_key: true
      t.references :assistant, null: false, foreign_key: { to_table: :marcosx_ai_assistants }
      t.string :title, null: false
      t.string :key_type, null: false
      t.string :key, null: false
      t.string :merchant_name, null: false
      t.text :description, null: false, default: ''
      t.integer :position
      t.timestamps
    end
    add_index :marcosx_ai_pix_keys, [:assistant_id, :position], unique: true
    add_index :marcosx_ai_pix_keys, [:assistant_id, :key], unique: true
    add_check_constraint :marcosx_ai_pix_keys, 'position IN (1, 2)', name: 'marcosx_ai_pix_active_slots'
  end
end
