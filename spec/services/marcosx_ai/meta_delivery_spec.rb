require 'rails_helper'

RSpec.describe 'MarcoXIA Meta delivery' do
  let(:account) { create(:account) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }

  before do
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
  end

  [[:channel_facebook_page, Facebook::SendOnFacebookService, :fb_text_message_params],
   [:channel_facebook_page, Instagram::Messenger::SendOnInstagramService, :message_params],
   [:channel_instagram, Instagram::SendOnInstagramService, :message_params]].each do |factory, service, payload_method|
    context service.name do
      let(:channel) { create(factory, account: account) }
      let(:inbox) { create(:inbox, account: account, channel: channel) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }
      let(:message) { create(:message, message_type: :outgoing, account: account, inbox: inbox, conversation: conversation, sender: assistant) }

      it 'never labels an AI reply as a human agent message' do
        allow(GlobalConfigService).to receive(:load).and_call_original
        allow(GlobalConfigService).to receive(:load).with('ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT', nil).and_return(true)
        allow(GlobalConfig).to receive(:get).and_call_original
        allow(GlobalConfig).to receive(:get).with('ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT').and_return(
          'ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT' => true, 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT' => true
        )
        allow(GlobalConfig).to receive(:get).with('ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT').and_return(
          'ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT' => true
        )
        payload = service.new(message: message).send(payload_method)
        expect(payload[:tag]).to be_nil
        expect(payload[:messaging_type]).not_to eq('MESSAGE_TAG')
      end

      it 'keeps automated replies inside the standard window even when human replies remain available' do
        create(:message, account: account, inbox: inbox, conversation: conversation, created_at: 2.days.ago)
        allow(conversation).to receive(:can_reply?).and_return(true)
        expect(assistant.accepts_conversation?(conversation)).to be(false)
        create(:message, account: account, inbox: inbox, conversation: conversation, created_at: 1.minute.ago)
        expect(assistant.accepts_conversation?(conversation)).to be(true)
      end
    end
  end
end
