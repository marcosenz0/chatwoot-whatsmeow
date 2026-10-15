require 'rails_helper'

RSpec.describe 'MarcoXIA scoped catalogs and notices' do
  let(:account) { create(:account) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:same_contact) { create(:conversation, account: account, inbox: inbox, contact: conversation.contact) }
  let(:other) { create(:conversation, account: account, inbox: inbox) }
  let(:resource) {
    assistant.resources.create!(account: account, title: 'Private sheet', description: 'Private information', kind: 'link',
                                url: 'https://example.com/private', audience: 'conversation', conversation: conversation)
  }
  let(:key) {
    assistant.pix_keys.create!(account: account, title: 'Private Pix', key_type: 'EMAIL', key: 'pix@example.com', merchant_name: 'Holder',
                               position: 1, audience: 'contacts', contact_ids: [conversation.contact_id])
  }
  let(:target) {
    assistant.notification_targets.create!(account: account, inbox: inbox, number: '+15555550101', audience: 'contacts',
                                           contact_ids: [conversation.contact_id])
  }

  it 'makes conversation-only items unavailable even in another conversation of the same contact' do
    resource
    expect(MarcosxAi::ResourceCatalog.instructions(assistant, conversation: conversation)).to include(resource.title)
    [nil, same_contact, other, create(:conversation)].each do |context|
      expect(MarcosxAi::ResourceCatalog.instructions(assistant, conversation: context)).not_to include(resource.title)
      expect { MarcosxAi::ResourceCatalog.validate!([resource.id], assistant, conversation: context) }.to raise_error(CustomExceptions::MarcosxAi)
    end
    resource.update!(audience: 'contacts', conversation: nil, contact_ids: [conversation.contact_id])
    expect(assistant.resources.available_to(same_contact)).to include(resource)
    expect(assistant.resources.available_to(other)).to be_empty
    resource.update!(audience: 'global', contact_ids: [])
    expect(assistant.resources.available_to(other)).to include(resource)
  end

  it 'filters the Pix prompt and validation without exposing keys or the selected contact list to the model' do
    key
    prompt = MarcosxAi::PromptBuilder.messages(assistant: assistant, conversation: conversation).first[:content]
    expect(prompt).to include(key.title)
    expect(prompt).not_to include(key.key, 'audience_contacts', 'contact_ids')
    expect(MarcosxAi::PromptBuilder.context_for(conversation, assistant: assistant)[:pix_available]).to be(true)
    expect(MarcosxAi::PromptBuilder.context_for(other, assistant: assistant)[:pix_available]).to be(false)
    expect(MarcosxAi::PixCatalog.instructions(assistant, conversation: other)).not_to include(key.title)
    expect { MarcosxAi::PixCatalog.validate!(key.id, assistant, conversation: other) }.to raise_error(CustomExceptions::MarcosxAi)
    expect { MarcosxAi::PixCatalog.validate!(key.id, assistant, conversation: same_contact) }.not_to raise_error
  end

  it 'revalidates resource and Pix scopes immediately before a queued delivery' do
    state = MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant)
    job = MarcosxAi::DeliveryJob.new
    job.instance_variable_set(:@state, state)
    resource.update!(audience: 'contacts', conversation: nil, contact_ids: [other.contact_id])
    key.update!(contact_ids: [other.contact_id])
    expect do
      expect(job.send(:create_resource_message, resource.id)).to be_nil
      expect(job.send(:create_pix_message, key.id)).to be_nil
    end.not_to change(Message, :count)
  end

  it 'keeps scoped notification numbers out of other contacts even when an old rule contains the same phone' do
    target
    assistant.update!(config: { notifications: { user_ids: [], whatsapp_numbers: [target.number], inbox_id: inbox.id } })
    allowed = MarcosxAi::NotificationRecipients.configuration(assistant: assistant, conversation: same_contact)
    expect(allowed['whatsapp_numbers']).to eq([target.number])
    expect(allowed['whatsapp_routes']).to eq(target.number => inbox.id)
    expect(MarcosxAi::NotificationRecipients.configuration(assistant: assistant, conversation: other)['whatsapp_numbers']).to eq([])
    target.update!(enabled: false)
    expect(MarcosxAi::NotificationRecipients.configuration(assistant: assistant, conversation: conversation)['whatsapp_numbers']).to eq([])
  end

  it 'cancels pending notices after removing a contact from their audience without opening a destination conversation' do
    configuration = MarcosxAi::NotificationRecipients.configuration(assistant: assistant, conversation: conversation) if target
    alert = assistant.alerts.create!(account: account, conversation: conversation, rule_id: 'help', name: 'Help', action: 'notify',
                                     configuration: configuration, status: 'open')
    delivery = alert.deliveries.create!(kind: 'whatsapp', recipient: target.number)
    target.update!(contact_ids: [other.contact_id])
    expect(Whatsmeow::DirectConversationBuilder).not_to receive(:new)
    expect { MarcosxAi::AlertDeliveryJob.perform_now(delivery.id) }.not_to change(Message, :count)
    expect(delivery.reload.status).to eq('cancelled')
    target.destroy!
    expect(MarcosxAi::NotificationRecipients.allowed_delivery?(alert, delivery.recipient)).to be(false)
  end

  it 'routes allowed notices through the registered inbox while preserving legacy default numbers' do
    other_inbox = create(:channel_whatsmeow, account: account).inbox
    target.update!(inbox: other_inbox)
    assistant.update!(config: { notifications: { user_ids: [], whatsapp_numbers: ['+15555550102'], inbox_id: inbox.id } })
    configuration = MarcosxAi::NotificationRecipients.configuration(assistant: assistant, conversation: conversation)
    expect(configuration['whatsapp_numbers']).to contain_exactly(target.number, '+15555550102')
    alert = assistant.alerts.create!(account: account, conversation: conversation, rule_id: 'help', name: 'Help', action: 'notify',
                                     configuration: configuration, status: 'open')
    delivery = alert.deliveries.create!(kind: 'whatsapp', recipient: target.number)
    destination = create(:conversation, account: account, inbox: other_inbox)
    builder = instance_double(Whatsmeow::DirectConversationBuilder, perform: destination)
    allow(Whatsmeow::DirectConversationBuilder).to receive(:new).with(inbox: other_inbox, params: anything).and_return(builder)
    with_modified_env FRONTEND_URL: 'https://example.com' do
      MarcosxAi::AlertDeliveryJob.perform_now(delivery.id)
    end
    expect(delivery.reload.status).to eq('queued'), delivery.error
    expect(delivery.message.inbox).to eq(other_inbox)
  end
end
