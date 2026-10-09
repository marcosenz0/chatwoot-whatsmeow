require 'rails_helper'

RSpec.describe MarcosxAi::MissedCallJob do
  include ActiveJob::TestHelper
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', config: { reply_to_missed_calls: true }) }
  let(:state) { MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant) }
  let(:call) do
    WhatsmeowCall.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact,
                          source_id: 'call', peer_jid: '5563999999999@s.whatsapp.net', direction: 'incoming', status: 'missed',
                          started_at: 2.minutes.ago, ended_at: 1.minute.ago)
  end

  before do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    state.resume!(manual: true)
    Whatsmeow::CallMessageService.new(call: call).perform
    clear_enqueued_jobs
  end

  it 'schedules one reply after an incoming missed call in the individually active pilot' do
    expect { described_class.perform_now(call.id) }.to have_enqueued_job(MarcosxAi::ResponseJob).once
    expect { described_class.perform_now(call.id) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
    expect(state.reload.metadata['call_event']).to include('status' => 'missed')
  end

  it 'ignores answered and outgoing calls' do
    call.update!(connected_at: 90.seconds.ago, status: 'completed')
    expect { described_class.perform_now(call.id) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
    call.update!(connected_at: nil, direction: 'outgoing', status: 'unanswered')
    expect { described_class.perform_now(call.id) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
  end

  it 'does not reply after a public human response or a manual pause' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: create(:user, account: account))
    expect { described_class.perform_now(call.id) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
    call.update!(ai_processed_at: nil)
    state.pause_by_agent!
    expect { described_class.perform_now(call.id) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
  end

  it 'dispatches only the newly ended incoming event and excludes imported history' do
    params = { 'call_id' => 'live', 'peer_jid' => '5563999999999@s.whatsapp.net', 'conversation_id' => conversation.id,
               'direction' => 'incoming', 'event' => 'call_ended', 'timestamp' => Time.current.to_i }
    expect { Whatsmeow::CallEventService.new(inbox: inbox, params: params).perform }.to have_enqueued_job(described_class).once
    expect { Whatsmeow::CallEventService.new(inbox: inbox, params: params).perform }.not_to have_enqueued_job(described_class)
    expect { Whatsmeow::CallEventService.new(inbox: inbox, params: params.merge('call_id' => 'import', 'historical' => true)).perform }
      .not_to have_enqueued_job(described_class)
  end
end
