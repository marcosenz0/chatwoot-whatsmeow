class Api::V1::Accounts::ConversationPipelinesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_pipeline, except: [:index, :create]

  def index
    Pipelines::DefaultSeeder.new(account: Current.account).perform!
    @pipelines = policy_scope(Current.account.conversation_pipelines).active.includes(:active_stages).ordered
    render json: { payload: @pipelines.map(&:push_event_data) }
  end

  def show
    render json: { payload: @pipeline.push_event_data }
  end

  def create
    ActiveRecord::Base.transaction do
      @pipeline = Current.account.conversation_pipelines.create!(pipeline_params)
      create_stages!(@pipeline)
    end

    render json: @pipeline.push_event_data
  end

  def update
    @pipeline.update!(pipeline_params)
    render json: @pipeline.push_event_data
  end

  def destroy
    return render_could_not_create_error('At least one active pipeline is required') if only_active_pipeline?

    was_default = @pipeline.default?
    @pipeline.update!(archived: true, default: false)
    set_new_default_pipeline if was_default
    head :ok
  end

  def board
    board = Pipelines::BoardBuilder.new(
      account: Current.account,
      user: Current.user,
      pipeline: @pipeline,
      params: params
    ).perform
    render json: { payload: board }
  end

  def reorder_stages
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
    @pipeline = Current.account.conversation_pipelines.active.find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(:name, :internal_name, :description, :color, :position, :default)
  end

  def stage_params
    params.permit(stages: [:name, :internal_name, :color, :category, :probability, :stale_after_days, :position])[:stages]
  end

  def create_stages!(pipeline)
    stages = stage_params.presence || Pipelines::DefaultSeeder::DEFAULT_STAGES
    stages.each_with_index do |stage, index|
      stage_attributes = stage.to_h.symbolize_keys
      pipeline.stages.create!(stage_attributes.merge(account: Current.account, position: stage_attributes[:position] || index))
    end
  end

  def only_active_pipeline?
    Current.account.conversation_pipelines.active.where.not(id: @pipeline.id).blank?
  end

  def set_new_default_pipeline
    Current.account.conversation_pipelines.active.ordered.first&.update!(default: true)
  end
end
