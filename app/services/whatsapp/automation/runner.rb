# The runner intentionally keeps graph traversal and node execution together so
# a locked run has a single owner for every state transition.
# rubocop:disable Metrics/ClassLength
class Whatsapp::Automation::Runner
  MAX_STEPS_PER_EXECUTION = 50

  pattr_initialize [:run!]

  def perform
    execution_error = execute_with_lock
    ChatwootExceptionTracker.new(execution_error, account: run.account).capture_exception if execution_error
  ensure
    Current.reset
  end

  private

  delegate :whatsapp_automation, :contact, to: :run
  delegate :inbox, to: :whatsapp_automation

  def execute_with_lock
    execution_error = nil

    run.with_lock do
      next if execution_deferred?

      run.update!(status: :running, next_run_at: nil)
      execute_nodes
    rescue StandardError => e
      run.update!(status: :failed, last_error: e.message)
      execution_error = e
    end

    execution_error
  end

  def execution_deferred?
    return true if run.status.in?(%w[completed failed cancelled])
    return cancel_disabled_run unless whatsapp_automation.reload.enabled?
    return true if run.waiting_reply?
    return reschedule_waiting_run if run.waiting? && run.next_run_at&.future?

    false
  end

  def execute_nodes
    MAX_STEPS_PER_EXECUTION.times do
      return complete_run if run.current_node_id.blank?

      node = nodes_by_id[run.current_node_id]
      raise "Flow node #{run.current_node_id} no longer exists" if node.blank?

      return unless execute_node(node)
    end

    raise "Flow exceeded #{MAX_STEPS_PER_EXECUTION} consecutive steps"
  end

  def execute_node(node)
    case node['type']
    when 'message' then execute_message_node(node)
    when 'wait' then execute_wait_node(node)
    when 'condition' then execute_condition_node(node)
    when 'action' then execute_action_node(node)
    when 'end' then complete_run
    else advance_from(node['id'])
    end
  end

  def execute_message_node(node)
    config = node.fetch('config', {}).with_indifferent_access
    awaiting_message = awaiting_message_for(node)
    return resume_after_message_delivery(node, config, awaiting_message) if awaiting_message.present?

    conversation = ensure_conversation
    message = build_message(conversation, config)
    run.update!(
      conversation: conversation,
      current_node_id: node['id'],
      context: run.context.merge(
        'last_outgoing_message_id' => message.id,
        'awaiting_message_id' => message.id,
        'awaiting_node_id' => node['id']
      )
    )
    false
  end

  def awaiting_message_for(node)
    message_id = run.context['awaiting_message_id']
    return if message_id.blank?

    awaiting_node_id = run.context['awaiting_node_id']
    raise "Run is awaiting a message from node #{awaiting_node_id}" if awaiting_node_id != node['id']

    Message.find_by!(
      id: message_id,
      account_id: run.account_id,
      conversation_id: run.conversation_id
    )
  end

  def resume_after_message_delivery(node, config, message)
    return fail_run_for_message(message) if message.failed?
    return false unless message_accepted_by_provider?(message)

    context = run.context.except('awaiting_message_id', 'awaiting_node_id')
    buttons = Array(config[:buttons])

    if buttons.present?
      run.update!(
        status: :waiting_reply,
        current_node_id: node['id'],
        context: context.merge('expected_buttons' => buttons.as_json)
      )
      return false
    end

    run.update!(context: context)
    advance_from(node['id'])
  end

  def message_accepted_by_provider?(message)
    # Outgoing messages start as sent before the provider call; source_id confirms Meta accepted them.
    message.source_id.present? || message.delivered? || message.read?
  end

  def fail_run_for_message(message)
    error = message.external_error.presence || "WhatsApp message #{message.id} failed"
    run.update!(status: :failed, last_error: error)
    false
  end

  def build_message(conversation, config)
    mode = config[:mode].presence || 'session'
    validate_customer_service_window!(mode, conversation)

    params = {
      content: config[:text].presence || config[:preview_text].presence || config[:template_name],
      private: false,
      content_attributes: { whatsapp_automation_id: whatsapp_automation.id }
    }
    params.merge!(session_message_params(config)) if mode == 'session'
    params[:template_params] = template_params(config) if mode == 'template'

    Current.executed_by = whatsapp_automation
    Messages::MessageBuilder.new(nil, conversation, ActionController::Parameters.new(params)).perform
  end

  def validate_customer_service_window!(mode, conversation)
    return unless mode == 'session' && !conversation.can_reply?

    raise 'A free-form message cannot be sent outside the 24-hour customer service window'
  end

  def session_message_params(config)
    buttons = Array(config[:buttons])
    return {} if buttons.blank?

    {
      content_type: 'input_select',
      content_attributes: {
        whatsapp_automation_id: whatsapp_automation.id,
        items: buttons.map { |button| { title: button['title'], value: button['id'] } }
      }
    }
  end

  def template_params(config)
    {
      name: config[:template_name],
      namespace: config[:namespace],
      category: config[:category],
      language: config[:language].presence || 'en_US',
      processed_params: config[:processed_params] || {}
    }
  end

  def execute_wait_node(node)
    duration = node.fetch('config', {})['duration'].to_i
    next_node_id = next_node_id(node['id'])
    return complete_run if next_node_id.blank?

    next_run_at = duration.minutes.from_now
    run.update!(status: :waiting, current_node_id: next_node_id, next_run_at: next_run_at)
    Whatsapp::Automation::RunJob.set(wait_until: next_run_at).perform_later(run.id)
    false
  end

  def execute_condition_node(node)
    result = condition_matches?(node.fetch('config', {}).with_indifferent_access)
    advance_from(node['id'], result ? 'true' : 'false')
  end

  def condition_matches?(config)
    actual = condition_value(config[:field])
    expected = config[:value]

    case config[:operator]
    when 'equals' then actual.to_s.casecmp?(expected.to_s)
    when 'not_equals' then !actual.to_s.casecmp?(expected.to_s)
    when 'contains' then actual.to_s.downcase.include?(expected.to_s.downcase)
    when 'present' then actual.present?
    when 'has_label' then contact.label_list.include?(expected.to_s)
    else false
    end
  end

  def condition_value(field)
    return run.context['last_button_id'] if field == 'last_button_id'
    return contact.custom_attributes[field.delete_prefix('custom.')] if field.to_s.start_with?('custom.')

    contact.public_send(field) if %w[name email phone_number].include?(field)
  end

  def execute_action_node(node)
    config = node.fetch('config', {}).with_indifferent_access
    case config[:action]
    when 'add_label'
      contact.add_labels(config[:value])
    when 'remove_label'
      contact.update!(label_list: contact.label_list - [config[:value]])
    when 'open_conversation'
      ensure_conversation.update!(status: :open)
    when 'resolve_conversation'
      ensure_conversation.update!(status: :resolved)
    end
    advance_from(node['id'])
  end

  def ensure_conversation
    return run.conversation if run.conversation.present?

    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    conversation = contact_inbox.conversations.where.not(status: :resolved).last ||
                   contact_inbox.conversations.last ||
                   Conversation.create!(
                     account: run.account,
                     inbox: inbox,
                     contact: contact,
                     contact_inbox: contact_inbox
                   )
    run.update!(conversation: conversation)
    conversation
  end

  def advance_from(source_id, source_handle = 'default')
    target = next_node_id(source_id, source_handle)
    return complete_run if target.blank?

    run.update!(current_node_id: target)
    true
  end

  def next_node_id(source_id, source_handle = 'default')
    matching_edge(source_id, source_handle)&.dig('target') ||
      matching_edge(source_id, 'default')&.dig('target')
  end

  def matching_edge(source_id, source_handle)
    edges.find do |edge|
      handle = edge['source_handle'].presence || 'default'
      edge['source'] == source_id && handle.to_s == source_handle.to_s
    end
  end

  def complete_run
    run.update!(status: :completed, current_node_id: nil, next_run_at: nil)
    false
  end

  def reschedule_waiting_run
    Whatsapp::Automation::RunJob.set(wait_until: run.next_run_at).perform_later(run.id)
  end

  def cancel_disabled_run
    run.update!(status: :cancelled, next_run_at: nil)
  end

  def nodes_by_id
    @nodes_by_id ||= whatsapp_automation.definition.fetch('nodes', []).index_by { |node| node['id'] }
  end

  def edges
    @edges ||= whatsapp_automation.definition.fetch('edges', [])
  end
end
# rubocop:enable Metrics/ClassLength
