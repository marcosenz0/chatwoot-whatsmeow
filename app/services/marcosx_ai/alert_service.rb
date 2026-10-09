class MarcosxAi::AlertService
  NOTICE_PREFIX = '[MarcoXIA:OPERATIONAL]'.freeze

  def self.perform(state:, plan:)
    rules = state.assistant.alert_rules.select { |rule| plan.fetch('alert_rule_ids', []).include?(rule[:id]) }
    if plan['handoff'] && state.assistant.feature_enabled?(:pause_on_handoff)
      rules << { id: 'human_handoff', name: I18n.t('marcosx_ai.human_attention'), action: 'pause',
                 description: plan['handoff_reason'], message: '{contact} · {inbox}\n{reason}\n{url}' }.with_indifferent_access
    end
    rules.each do |rule|
      alert = MarcosxAi::Alert.create_or_find_by!(conversation: state.conversation, rule_id: rule[:id], status: 'open') do |record|
        record.account = state.account
        record.assistant = state.assistant
        record.name = rule[:name]
        record.action = rule[:action]
        record.reason = rule[:description].to_s.first(500)
        record.configuration = state.assistant.resolved_config[:notifications].merge(rule).stringify_keys
      end
      state.wait_for_human!(reason: alert.name) if alert.action == 'pause' && state.status != 'awaiting_human'
      queue(alert)
    end
    state.status == 'awaiting_human'
  end

  def self.queue(alert)
    configuration = alert.configuration
    configuration.fetch('user_ids', []).each do |id|
      alert.deliveries.create_or_find_by!(kind: 'panel', recipient: id.to_s)
    end
    configuration.fetch('whatsapp_numbers', []).each do |number|
      alert.deliveries.create_or_find_by!(kind: 'whatsapp', recipient: number)
    end
  end

  def self.text(alert)
    conversation = alert.conversation
    values = { 'contact' => conversation.contact.name, 'inbox' => conversation.inbox.name, 'reason' => alert.reason,
               'url' => "#{ENV.fetch('FRONTEND_URL')}/app/accounts/#{alert.account_id}/conversations/#{conversation.display_id}" }
    template = alert.configuration['message'].presence || '{contact} · {inbox}\n{reason}\n{url}'
    "#{NOTICE_PREFIX} #{I18n.t('marcosx_ai.operational')}\n#{template.gsub(/\{(contact|inbox|reason|url)\}/) {
      values.fetch(Regexp.last_match(1)).to_s
    }}"
  end

  def self.prepare_delivery(state:, plan:, token:)
    return plan unless perform(state: state, plan: plan)
    return unless state.assistant.feature_enabled?(:pause_acknowledgement)

    state.update!(metadata: state.metadata.merge('run_token' => token, 'pause_ack' => true, 'processing' => true))
    plan.merge('messages' => plan['messages'].first(1), 'reaction' => nil)
  end
end
