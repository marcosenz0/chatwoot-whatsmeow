class Api::V1::Accounts::MarcosxAi::InboxesController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!, except: [:index]
  before_action :set_assistant

  def index
    render json: {
      inboxes: @assistant.marcosx_ai_inboxes.includes(:inbox).map { |record| serialize(record) },
      available_inboxes: Current.account.inboxes.order_by_name.map { |inbox| serialize_available(inbox) }
    }
  end

  def create
    inbox = Current.account.inboxes.find(inbox_params[:inbox_id])
    record = @assistant.marcosx_ai_inboxes.create!(account: Current.account, inbox: inbox)
    render json: { inbox: serialize(record) }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    record = @assistant.marcosx_ai_inboxes.find_by!(inbox_id: params[:inbox_id])
    record.destroy!
    head :no_content
  end

  private

  def set_assistant
    @assistant = Current.account.marcosx_ai_assistants.find(params[:assistant_id])
  end

  def inbox_params
    params.permit(:inbox_id)
  end

  def serialize(record)
    serialize_available(record.inbox).merge(
      marcosx_ai_inbox_id: record.id,
      assistant_id: record.assistant_id,
      connected: true
    )
  end

  def serialize_available(inbox)
    {
      id: inbox.id,
      name: inbox.name,
      channel_type: inbox.channel_type,
      inbox_type: inbox.inbox_type,
      connected_assistant_id: inbox.marcosx_ai_assistant&.id
    }
  end
end
