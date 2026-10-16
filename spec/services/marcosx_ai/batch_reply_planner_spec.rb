require 'rails_helper'

RSpec.describe MarcosxAi::BatchReplyPlanner do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Need help') }
  let(:batch) { assistant.reply_batches.create!(account: account, user: user, mode: 'review', request_id: SecureRandom.uuid) }
  let(:item) { batch.items.create!(conversation: conversation, trigger_message_id: message.id, assistant_version: assistant.updated_at.iso8601(6)) }
  let(:client) { instance_double(MarcosxAi::ProviderClient) }

  it 'uses the configured agent and current request without sending or persisting conversation state' do
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return({ messages: ['I can help'], reaction: nil, reaction_message_id: nil,
                                               handoff: false, handoff_reason: nil }.to_json)
    expect { described_class.perform(item) }.not_to change(MarcosxAi::ConversationState, :count)
    expect(client).to have_received(:chat) do |messages:, schema:|
      expect(messages.to_json).to include('Need help', 'latest_contact_request')
      expect(schema).to eq(MarcosxAi::ReplyPlan::SCHEMA)
    end
    expect(conversation.messages.outgoing).to be_empty
  end
end
