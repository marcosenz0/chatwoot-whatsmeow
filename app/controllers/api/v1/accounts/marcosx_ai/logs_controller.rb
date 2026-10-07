class Api::V1::Accounts::MarcosxAi::LogsController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!

  def index
    logs = Current.account.marcosx_ai_logs.includes(:assistant, :conversation).order(created_at: :desc).limit(50)
    render json: { logs: logs.map do |log|
      {
        id: log.id, event: log.event, status: log.status, assistant_name: log.assistant&.name,
        conversation_id: log.conversation&.display_id, response: log.response, error: log.error, created_at: log.created_at
      }
    end }
  end
end
