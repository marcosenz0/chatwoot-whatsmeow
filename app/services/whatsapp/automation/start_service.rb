class Whatsapp::Automation::StartService
  pattr_initialize [:automation!, :message!]

  def perform
    return unless automation.enabled?
    return unless automation.trigger_matches?(message)

    existing_run = automation.runs.unfinished.find_by(contact_id: message.sender_id)
    return existing_run if existing_run.present?

    run, created = create_run
    return run unless created

    enqueue_or_complete(run)
    run
  end

  private

  def create_run
    run = automation.runs.create!(
      account: automation.account,
      contact: message.sender,
      conversation: message.conversation,
      status: :queued,
      current_node_id: first_node_id,
      context: { trigger_message_id: message.id }
    )
    [run, true]
  rescue ActiveRecord::RecordNotUnique
    [automation.runs.unfinished.find_by!(contact_id: message.sender_id), false]
  end

  def enqueue_or_complete(run)
    if run.current_node_id.blank?
      run.completed!
    else
      Whatsapp::Automation::RunJob.perform_later(run.id)
    end
  end

  def first_node_id
    trigger = automation.definition.fetch('nodes', []).find { |node| node['type'] == 'trigger' }
    return if trigger.blank?

    automation.definition.fetch('edges', []).find do |edge|
      edge['source'] == trigger['id'] && edge['source_handle'].in?([nil, '', 'default'])
    end&.dig('target')
  end
end
