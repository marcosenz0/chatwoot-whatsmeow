class Api::V1::Accounts::ConversationPipelineStagesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_pipeline
  before_action :fetch_stage, only: [:update, :destroy]

  def create
    @stage = @pipeline.stages.create!(stage_params.merge(account: Current.account))
    render json: @stage.push_event_data
  end

  def update
    @stage.update!(stage_params)
    render json: @stage.push_event_data
  end

  def destroy
    return render_could_not_create_error('At least one active stage is required') if only_active_stage?

    ActiveRecord::Base.transaction do
      move_conversations_to_next_stage
      @stage.update!(archived: true)
    end
    head :ok
  end

  def reorder
    stage_positions = params.require(:stage_positions)
    ActiveRecord::Base.transaction do
      stage_positions.each_with_index do |stage_id, index|
        @pipeline.stages.find(stage_id).update!(position: index)
      end
    end

    render json: { payload: @pipeline.reload.push_event_data }
  end

  private

  def fetch_pipeline
    @pipeline = Current.account.conversation_pipelines.active.find(params[:conversation_pipeline_id])
  end

  def fetch_stage
    @stage = @pipeline.stages.active.find(params[:id])
  end

  def stage_params
    params.require(:stage).permit(:name, :internal_name, :color, :category, :probability, :stale_after_days, :position)
  end

  def only_active_stage?
    @pipeline.active_stages.where.not(id: @stage.id).blank?
  end

  def move_conversations_to_next_stage
    next_stage = @pipeline.active_stages.where.not(id: @stage.id).first
    # rubocop:disable Rails/SkipsModelValidations
    @stage.conversations.update_all(
      conversation_pipeline_stage_id: next_stage.id,
      pipeline_stage_entered_at: Time.current,
      updated_at: Time.current
    )
    # rubocop:enable Rails/SkipsModelValidations
  end
end
