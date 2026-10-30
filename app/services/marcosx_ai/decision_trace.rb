class MarcosxAi::DecisionTrace
  def self.write_note(state:, content:)
    state.conversation.messages.create!(
      account: state.account, inbox: state.inbox, sender: state.assistant, message_type: :outgoing, private: true, content: content,
      additional_attributes: { marcosx_ai: true, marcosx_ai_decision: state.metadata['last_decision']&.merge('status' => state.status) }
    )
  end

  def self.capture(state:, plan:, rules:)
    {
      'assistant_id' => state.assistant_id, 'assistant_version' => state.assistant.updated_at.iso8601(6),
      'reason' => plan['handoff_reason'], 'handoff_requested' => plan['handoff'] == true,
      'automatic_handoff_enabled' => state.automatic_handoff_enabled?, 'status' => state.status,
      'pause_on_handoff' => state.assistant.feature_enabled?(:pause_on_handoff),
      'rules' => rules.map { |rule| rule.slice(:id, :name, :description, :action) }.as_json,
      'trigger_message_id' => state.metadata['trigger_message_id'], 'recorded_at' => Time.current.iso8601
    }
  end

  def self.report(message:)
    assistant = message.sender
    trace = message.additional_attributes['marcosx_ai_decision']
    config = assistant.resolved_config
    automatic_handoff_enabled = message.conversation.marcosx_ai_conversation_state&.automatic_handoff_enabled? != false
    sources = [
      { field: 'system', text: assistant.instructions.presence || I18n.t('marcosx_ai.default_prompt'), section: 'prompt', editable: true },
      { field: 'editorial', text: config[:editorial_instructions] || MarcosxAi::PromptBuilder::EDITORIAL_INSTRUCTIONS,
        section: 'prompt', editable: true },
      { field: 'guidelines', text: assistant.response_guidelines.join("\n"), section: 'prompt', editable: true },
      { field: 'guardrails', text: assistant.guardrails.join("\n"), section: 'prompt', editable: true },
      { field: 'platform', text: MarcosxAi::PromptBuilder.platform_instructions(assistant, false, false, automatic_handoff_enabled)
                                                         .lines.grep(/externa|fora|humano|action=pause/).join, section: 'prompt', editable: true }
    ].reject { |source| source[:text].blank? }
    {
      note: message.content, assistant: { id: assistant.id, name: assistant.name }, snapshot: trace,
      configuration_changed: trace.present? && trace['assistant_version'] != assistant.updated_at.iso8601(6),
      sources: sources, rules: assistant.alert_rules.map { |rule| rule.slice(:id, :name, :description, :action) },
      pause_on_handoff: assistant.feature_enabled?(:pause_on_handoff),
      automatic_handoff_enabled: automatic_handoff_enabled
    }
  end
end
