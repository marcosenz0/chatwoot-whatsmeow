class AllowReusingArchivedPipelineNames < ActiveRecord::Migration[7.0]
  def change
    update_pipeline_internal_name_index
    update_stage_internal_name_index
  end

  private

  def update_pipeline_internal_name_index
    remove_index :conversation_pipelines, column: [:account_id, :internal_name], if_exists: true

    add_index :conversation_pipelines, [:account_id, :internal_name],
              unique: true,
              where: 'archived = false',
              name: 'idx_active_pipelines_on_account_and_name'
  end

  def update_stage_internal_name_index
    remove_index :conversation_pipeline_stages,
                 name: 'idx_pipeline_stages_on_pipeline_and_name',
                 if_exists: true

    add_index :conversation_pipeline_stages, [:conversation_pipeline_id, :internal_name],
              unique: true,
              where: 'archived = false',
              name: 'idx_active_pipeline_stages_on_pipeline_and_name'
  end
end
