class Api::V1::Accounts::MarcosxAi::ResourcesController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!
  before_action :set_assistant
  before_action :set_resource, only: [:update, :destroy]

  def index
    scope = @assistant.resources
    search = params[:search].to_s.strip
    scope = scope.where('title ILIKE :term OR description ILIKE :term', term: "%#{MarcosxAi::Resource.sanitize_sql_like(search)}%") if search.present?
    page = params[:page].to_i.clamp(1, 100_000)
    render json: { resources: scope.ordered.with_attached_file.offset((page - 1) * 24).limit(24).map(&:public_data),
                   total: scope.count, page: page, per_page: 24, limit: MarcosxAi::Resource::MAX_ITEMS }
  end

  def create
    @assistant.with_lock do
      if @assistant.resources.count >= MarcosxAi::Resource::MAX_ITEMS
        return render json: { error: I18n.t('marcosx_ai.errors.resource_limit') }, status: :unprocessable_entity
      end

      @resource = @assistant.resources.create!(resource_params.merge(account: Current.account))
    end
    render json: { resource: @resource.public_data }, status: :created
  rescue ActiveRecord::RecordInvalid, ArgumentError
    render_invalid
  end

  def update
    @resource.update!(resource_params)
    render json: { resource: @resource.public_data }
  rescue ActiveRecord::RecordInvalid, ArgumentError
    render_invalid
  end

  def destroy
    @resource.destroy!
    head :no_content
  end

  private

  def set_assistant
    @assistant = Current.account.marcosx_ai_assistants.find(params[:assistant_id])
  end

  def set_resource
    @resource = @assistant.resources.find(params[:id])
  end

  def resource_params
    data = params.require(:resource).permit(:title, :description, :kind, :url, :enabled, :file).to_h
    if data.key?('enabled')
      raise ArgumentError unless [true, false, 'true', 'false'].include?(data['enabled'])

      data['enabled'] = [true, 'true'].include?(data['enabled'])
    end
    if data.key?('file') && !data['file'].is_a?(ActionDispatch::Http::UploadedFile)
      raise ArgumentError
    end

    data
  end

  def render_invalid
    render json: { error: I18n.t('marcosx_ai.errors.invalid_resource') }, status: :unprocessable_entity
  end
end
