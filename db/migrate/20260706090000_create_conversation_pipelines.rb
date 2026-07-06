class CreateConversationPipelines < ActiveRecord::Migration[7.0]
  def change
    create_conversation_pipelines
    create_conversation_pipeline_stages
    add_pipeline_fields_to_conversations
  end

  private

  def create_conversation_pipelines
    create_table :conversation_pipelines do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :internal_name, null: false
      t.text :description
      t.string :color, null: false, default: '#1f93ff'
      t.integer :position, null: false
      t.boolean :default, null: false, default: false
      t.boolean :archived, null: false, default: false
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end

    add_index :conversation_pipelines, [:account_id, :internal_name], unique: true
    add_index :conversation_pipelines, [:account_id, :position]
    add_index :conversation_pipelines, [:account_id, :default], unique: true, where: '"default" = true'
  end

  def create_conversation_pipeline_stages
    create_table :conversation_pipeline_stages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation_pipeline, null: false, foreign_key: true
      t.string :name, null: false
      t.string :internal_name, null: false
      t.integer :position, null: false
      t.string :color, null: false, default: '#1f93ff'
      t.integer :category, null: false, default: 0
      t.integer :probability
      t.integer :stale_after_days
      t.boolean :archived, null: false, default: false
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end

    add_conversation_pipeline_stage_indexes
  end

  def add_conversation_pipeline_stage_indexes
    add_index :conversation_pipeline_stages,
              [:conversation_pipeline_id, :internal_name],
              unique: true,
              name: 'idx_pipeline_stages_on_pipeline_and_name'
    add_index :conversation_pipeline_stages, [:conversation_pipeline_id, :position],
              name: 'idx_pipeline_stages_on_pipeline_and_position'
    add_index :conversation_pipeline_stages, [:account_id, :conversation_pipeline_id],
              name: 'idx_pipeline_stages_on_account_and_pipeline'
  end

  def add_pipeline_fields_to_conversations
    add_reference :conversations, :conversation_pipeline, foreign_key: true
    add_reference :conversations, :conversation_pipeline_stage, foreign_key: true
    add_column :conversations, :pipeline_stage_entered_at, :datetime
    add_index :conversations, [:account_id, :conversation_pipeline_id], name: 'idx_conversations_on_account_pipeline'
    add_index :conversations, [:account_id, :conversation_pipeline_stage_id, :status, :last_activity_at],
              name: 'idx_conversations_on_account_stage_status_activity'
  end
end
