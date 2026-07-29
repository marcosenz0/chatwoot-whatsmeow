class Whatsapp::Automation::InboundMessageService
  pattr_initialize [:message!]

  def perform
    return unless eligible_message?

    resumed_a_run = resume_waiting_runs
    start_matching_automations unless resumed_a_run
  end

  private

  delegate :conversation, to: :message

  def eligible_message?
    message.incoming? &&
      message.sender.is_a?(Contact) &&
      conversation.inbox.channel_type == 'Channel::Whatsapp' &&
      conversation.inbox.channel.provider == 'whatsapp_cloud'
  end

  def resume_waiting_runs
    candidates = reply_candidate_runs.filter_map do |run|
      selected_button = selected_button_for(run)
      [run, selected_button] if selected_button.present?
    end
    candidate = matching_reply_candidate(candidates)
    return false if candidate.blank?

    resume_run(*candidate)
  end

  def resume_run(run, selected_button)
    next_node_id = next_node_id_for(run.whatsapp_automation, run.current_node_id, selected_button['id'])
    return false unless advance_run(run, selected_button, next_node_id)

    Whatsapp::Automation::RunJob.perform_later(run.id) if next_node_id.present?
    true
  end

  def reply_candidate_runs
    WhatsappAutomationRun.where(status: [:running, :waiting_reply])
                         .joins(:whatsapp_automation)
                         .where(
                           contact_id: message.sender_id,
                           whatsapp_automations: { inbox_id: conversation.inbox_id, status: WhatsappAutomation.statuses[:active] }
                         ).to_a
  end

  def matching_reply_candidate(candidates)
    return if candidates.empty?
    return candidates.find { |run, _button| reply_targets_run?(run) } if reply_context_present?

    waiting_candidates = candidates.select { |run, _button| run.waiting_reply? }
    waiting_candidates.first if waiting_candidates.one?
  end

  def reply_targets_run?(run)
    attributes = message.content_attributes.to_h.with_indifferent_access
    outgoing_message_id = run.context['last_outgoing_message_id']
    return false if outgoing_message_id.blank?
    return true if attributes[:in_reply_to].to_s == outgoing_message_id.to_s
    return false if attributes[:in_reply_to_external_id].blank?

    outgoing_message = Message.find_by(
      id: outgoing_message_id,
      account_id: run.account_id,
      conversation_id: run.conversation_id
    )
    outgoing_message&.source_id.to_s == attributes[:in_reply_to_external_id].to_s
  end

  def reply_context_present?
    attributes = message.content_attributes.to_h.with_indifferent_access
    attributes[:in_reply_to].present? || attributes[:in_reply_to_external_id].present?
  end

  def selected_button_for(run)
    reply = interactive_reply
    expected_buttons_for(run).find do |button|
      button['id'].to_s == reply[:id].to_s || button['title'].to_s.casecmp?(reply[:title].to_s)
    end
  end

  def expected_buttons_for(run)
    expected_buttons = Array(run.context['expected_buttons'])
    return expected_buttons if expected_buttons.present?
    return [] unless run.running? && run.context['awaiting_message_id'].present?

    node = run.whatsapp_automation.definition.fetch('nodes', []).find { |item| item['id'] == run.current_node_id }
    Array(node&.dig('config', 'buttons'))
  end

  def advance_run(run, selected_button, next_node_id)
    advanced = false
    run.with_lock do
      if reply_ready?(run)
        run.update!(
          status: next_node_id.present? ? :running : :completed,
          current_node_id: next_node_id,
          context: run.context.except('awaiting_message_id', 'awaiting_node_id', 'expected_buttons').merge(
            'last_button_id' => selected_button['id'],
            'last_button_title' => selected_button['title'],
            'last_reply_message_id' => message.id
          )
        )
        advanced = true
      end
    end
    advanced
  end

  def reply_ready?(run)
    return true if run.waiting_reply?

    run.running? &&
      run.context['awaiting_message_id'].present? &&
      reply_context_present? &&
      reply_targets_run?(run)
  end

  def interactive_reply
    attributes = message.content_attributes&.dig('whatsapp_interactive_reply') || {}
    {
      id: attributes['id'].presence || message.content,
      title: attributes['title'].presence || message.content
    }
  end

  def next_node_id_for(automation, source_id, source_handle)
    edges = automation.definition.fetch('edges', [])
    matching_edge(edges, source_id, source_handle)&.dig('target') ||
      matching_edge(edges, source_id, 'default')&.dig('target')
  end

  def matching_edge(edges, source_id, source_handle)
    edges.find do |edge|
      handle = edge['source_handle'].presence || 'default'
      edge['source'] == source_id && handle.to_s == source_handle.to_s
    end
  end

  def start_matching_automations
    WhatsappAutomation.enabled.where(inbox_id: conversation.inbox_id).find_each do |automation|
      Whatsapp::Automation::StartService.new(automation: automation, message: message).perform
    end
  end
end
