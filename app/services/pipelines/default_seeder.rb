class Pipelines::DefaultSeeder
  DEFAULT_STAGES = [
    { name: 'Novo lead', color: '#2563eb', category: 'open', probability: 10, stale_after_days: 1 },
    { name: 'Contato feito', color: '#0891b2', category: 'open', probability: 25, stale_after_days: 2 },
    { name: 'Qualificado', color: '#059669', category: 'open', probability: 50, stale_after_days: 3 },
    { name: 'Proposta enviada', color: '#d97706', category: 'open', probability: 70, stale_after_days: 5 },
    { name: 'Negociação', color: '#7c3aed', category: 'open', probability: 85, stale_after_days: 7 },
    { name: 'Ganho', color: '#16a34a', category: 'won', probability: 100, stale_after_days: nil },
    { name: 'Perdido', color: '#dc2626', category: 'lost', probability: 0, stale_after_days: nil }
  ].freeze

  pattr_initialize [:account!]

  def perform!
    return account.conversation_pipelines.active.ordered.first if account.conversation_pipelines.active.exists?

    ActiveRecord::Base.transaction do
      pipeline = account.conversation_pipelines.create!(
        name: 'Funil principal',
        internal_name: 'funil_principal',
        description: 'Pipeline padrão para acompanhar leads e oportunidades nas conversas.',
        color: '#2563eb',
        default: true
      )

      create_default_stages!(pipeline)
      backfill_open_conversations!(pipeline)
      pipeline
    end
  end

  def create_default_stages!(pipeline)
    DEFAULT_STAGES.each_with_index do |stage_params, index|
      pipeline.stages.create!(stage_params.merge(account: account, position: index))
    end
  end

  private

  def backfill_open_conversations!(pipeline)
    first_stage = pipeline.active_stages.first
    return if first_stage.blank?

    # rubocop:disable Rails/SkipsModelValidations
    account.conversations.where(conversation_pipeline_id: nil).open.update_all(
      conversation_pipeline_id: pipeline.id,
      conversation_pipeline_stage_id: first_stage.id,
      pipeline_stage_entered_at: Time.current,
      updated_at: Time.current
    )
    # rubocop:enable Rails/SkipsModelValidations
  end
end
