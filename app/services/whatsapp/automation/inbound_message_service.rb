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
    resumed_a_run = false
    WhatsappAutomationRun.waiting_reply
                         .joins(:whatsapp_automation)
                         .where(
                           contact_id: message.sender_id,
                           whatsapp_automations: { inbox_id: conversation.inbox_id, status: WhatsappAutomation.statuses[:active] }
                         ).find_each do |run|
      resumed_a_run = resume_run(run) || resumed_a_run
    end
    resumed_a_run
  end

  def resume_run(run)
    selected_button = selected_button_for(run)
    return false if selected_button.blank?

    next_node_id = next_node_id_for(run.whatsapp_automation, run.current_node_id, selected_button['id'])
    return false unless advance_run(run, selected_button, next_node_id)

    Whatsapp::Automation::RunJob.perform_later(run.id) if next_node_id.present?
    true
  end

  def selected_button_for(run)
    reply = interactive_reply
    Array(run.context['expected_buttons']).find do |button|
      button['id'].to_s == reply[:id].to_s || button['title'].to_s.casecmp?(reply[:title].to_s)
    end
  end

  def advance_run(run, selected_button, next_node_id)
    advanced = false
    run.with_lock do
      if run.waiting_reply?
        run.update!(
          status: next_node_id.present? ? :running : :completed,
          current_node_id: next_node_id,
          context: run.context.merge(
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
