class Whatsapp::Automation::CampaignRunService
  pattr_initialize [:campaign!, :contact!, :conversation!, :message!]

  def perform
    return if automation.blank? || trigger.blank? || buttons.empty?

    automation.runs.transaction do
      cancel_existing_runs
      create_waiting_run
    end
  end

  private

  def automation
    @automation ||= campaign.account.whatsapp_automations.enabled.find_by(
      id: campaign.trigger_rules['whatsapp_automation_id'],
      inbox_id: campaign.inbox_id,
      trigger_type: 'campaign_reply'
    )
  end

  def trigger
    @trigger ||= automation.definition.fetch('nodes', []).find { |node| node['type'] == 'trigger' }
  end

  def buttons
    @buttons ||= Array(trigger&.dig('config', 'buttons'))
  end

  def cancel_existing_runs
    automation.runs.unfinished.where(contact: contact).find_each do |run|
      run.update!(status: :cancelled, next_run_at: nil)
    end
  end

  def create_waiting_run
    automation.runs.create!(
      account: campaign.account,
      contact: contact,
      conversation: conversation,
      status: :waiting_reply,
      current_node_id: trigger['id'],
      context: {
        'campaign_id' => campaign.id,
        'last_outgoing_message_id' => message.id,
        'expected_buttons' => buttons
      }
    )
  end
end
