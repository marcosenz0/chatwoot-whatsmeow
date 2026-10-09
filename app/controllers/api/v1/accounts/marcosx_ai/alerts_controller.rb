class Api::V1::Accounts::MarcosxAi::AlertsController < Api::V1::Accounts::MarcosxAi::BaseController
  def index
    alerts = MarcosxAi::Alert.where(account: Current.account)
    alerts = alerts.where(assistant_id: params[:assistant_id]) if params[:assistant_id]
    alerts = alerts.joins(:conversation).where(conversations: { display_id: params[:conversation_id] }) if params[:conversation_id]
    render json: { alerts: alerts.includes(:deliveries, conversation: :contact).order(created_at: :desc).limit(100).filter_map do |alert|
      alert.public_data if policy(alert.conversation).show?
    end }
  end

  def update
    alert = MarcosxAi::Alert.where(account: Current.account).find(params[:id])
    authorize alert.conversation, :show?
    alert.with_lock do
      alert.update!(status: 'resolved', resolved_by: Current.user, resolved_at: Time.current) if alert.status == 'open'
    end
    render json: { alert: alert.public_data }
  end
end
