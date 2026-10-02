require 'rails_helper'

RSpec.describe Whatsmeow::GroupChangeService do
  let(:inbox) { create(:channel_whatsmeow).inbox }
  let(:params) do
    { 'group_jid' => '120363000000001@g.us', 'group_name' => 'Test group', 'timestamp' => Time.current.to_i,
      'version' => '1', 'changes' => [{ 'kind' => 'join', 'names' => 'Test participant' }] }
  end

  it 'records the member change once when a webhook is repeated' do
    2.times { described_class.new(inbox: inbox, params: params).perform }
    messages = inbox.messages.where("(content_attributes #>> '{}')::jsonb ->> 'whatsmeow_group_change' = 'true'")
    expect(messages.count).to eq(1)
    expect(messages.first.content).to include('Test participant')
    expect(messages.first).to be_activity
  end
end
