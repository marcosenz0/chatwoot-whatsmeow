class Api::V1::Accounts::MarcosxAi::TestSessionsController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :set_assistant

  def index
    page = params[:page].to_i.clamp(1, 100_000)
    sessions = scope.order(updated_at: :desc, id: :desc).offset((page - 1) * 25).limit(25)
    render json: { sessions: sessions.map(&:public_data), total: scope.count, page: page }
  end

  def show
    render json: { session: scope.find(params[:id]).public_data(detail: true) }
  end

  def create
    session = scope.create!(account: Current.account, assistant: @assistant, user: Current.user)
    render json: { session: session.public_data(detail: true) }, status: :created
  end

  def destroy
    scope.find(params[:id]).destroy!
    head :no_content
  end

  private

  def set_assistant
    @assistant = Current.account.marcosx_ai_assistants.find(params[:assistant_id])
  end

  def scope
    MarcosxAi::TestSession.where(account: Current.account, assistant: @assistant, user: Current.user)
  end
end
