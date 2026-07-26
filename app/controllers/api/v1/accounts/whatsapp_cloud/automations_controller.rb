class Api::V1::Accounts::WhatsappCloud::AutomationsController < Api::V1::Accounts::WhatsappCloud::BaseController
  before_action :automation, only: [:show, :update, :destroy, :publish, :pause]

  def index
    automations = Current.account.whatsapp_automations.includes(:inbox).order(updated_at: :desc)
    automations = automations.where(inbox_id: official_inbox.id) if params[:inbox_id].present?
    render json: automations.map { |record| automation_json(record) }
  end

  def show
    render json: automation_json(automation)
  end

  def create
    record = Current.account.whatsapp_automations.create!(automation_params)
    render json: automation_json(record), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_could_not_create_error(e.record.errors.full_messages)
  end

  def update
    automation.update!(automation_params)
    render json: automation_json(automation)
  rescue ActiveRecord::RecordInvalid => e
    render_could_not_create_error(e.record.errors.full_messages)
  end

  def destroy
    automation.destroy!
    head :ok
  end

  def publish
    automation.publish!
    render json: automation_json(automation)
  rescue ActiveRecord::RecordInvalid => e
    render_could_not_create_error(e.record.errors.full_messages)
  end

  def pause
    automation.pause!
    render json: automation_json(automation)
  end

  private

  def automation
    @automation ||= Current.account.whatsapp_automations.find(params[:id])
  end

  def automation_params
    permitted = params.require(:automation).permit(
      :name,
      :description,
      :inbox_id,
      :trigger_type,
      trigger_config: {},
      definition: {}
    )
    permitted[:inbox_id] = official_inbox(permitted[:inbox_id]).id if permitted[:inbox_id].present?
    permitted
  end

  def automation_json(record)
    {
      id: record.id,
      account_id: record.account_id,
      inbox_id: record.inbox_id,
      inbox_name: record.inbox.name,
      name: record.name,
      description: record.description,
      status: record.status,
      trigger_type: record.trigger_type,
      trigger_config: record.trigger_config,
      definition: record.definition,
      published_at: record.published_at,
      created_at: record.created_at,
      updated_at: record.updated_at,
      run_summary: run_summary(record)
    }
  end

  def run_summary(record)
    counts = record.runs.group(:status).count
    {
      total: counts.values.sum,
      running: counts.fetch('running', 0) + counts.fetch('waiting', 0) + counts.fetch('waiting_reply', 0),
      completed: counts.fetch('completed', 0),
      failed: counts.fetch('failed', 0)
    }
  end
end
