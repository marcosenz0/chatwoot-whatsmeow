class Api::V1::Accounts::MarcosxAi::NotificationTargetsController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!
  before_action :set_assistant

  def index
    render_targets
  end

  def create
    @assistant.with_lock do
      @assistant.notification_targets.create!(target_params.merge(account: Current.account))
    end
    render_targets(:created)
  rescue ActiveRecord::RecordInvalid, ArgumentError
    render_invalid
  end

  def update
    @assistant.with_lock do
      item = find_target
      old_number = item.number
      item.update!(target_params)
      MarcosxAi::NotificationRecipients.remove_legacy!(@assistant, old_number)
    end
    render_targets
  rescue ActiveRecord::RecordInvalid, ArgumentError
    render_invalid
  end

  def destroy
    @assistant.with_lock do
      item = find_target
      number = item.number
      item.destroy! if item.persisted?
      MarcosxAi::NotificationRecipients.remove_legacy!(@assistant, number)
    end
    render_targets
  end

  private

  def set_assistant
    @assistant = Current.account.marcosx_ai_assistants.find(params[:assistant_id])
  end

  def find_target
    return @assistant.notification_targets.find(params[:id]) unless params[:id].start_with?('legacy_')

    entry = MarcosxAi::NotificationRecipients.legacy(@assistant).find { |item| item[:id] == params[:id] }
    raise ActiveRecord::RecordNotFound unless entry

    @assistant.notification_targets.new(entry.slice(:title, :number, :inbox_id, :enabled).merge(account: Current.account))
  end

  def target_params
    entry = params.require(:notification_target)
    data = entry.permit(:title, :number, :inbox_id, :enabled).to_h
    raise ArgumentError if data.except('enabled', 'inbox_id').values.any? { |value| !value.is_a?(String) }
    raise ArgumentError if data.key?('enabled') && ![true, false].include?(data['enabled'])
    raise ArgumentError if data.key?('inbox_id') && !(data['inbox_id'].is_a?(Integer) && data['inbox_id'].positive?)

    data.merge(MarcosxAi::AudienceParams.parse(entry, account: Current.account))
  end

  def render_targets(status = :ok)
    render json: { notification_targets: MarcosxAi::NotificationRecipients.list(@assistant) }, status: status
  end

  def render_invalid
    render json: { error: I18n.t('marcosx_ai.errors.invalid_notification_target') }, status: :unprocessable_entity
  end
end
