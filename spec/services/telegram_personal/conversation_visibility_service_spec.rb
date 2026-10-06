require 'rails_helper'

RSpec.describe TelegramPersonal::ConversationVisibilityService do
  let(:channel) { create(:channel_telegram_personal) }
  let(:inbox) { channel.inbox }
  let!(:direct) { create(:conversation, inbox: inbox, account: inbox.account) }
  let!(:group) { create(:conversation, inbox: inbox, account: inbox.account, additional_attributes: { telegram_group: true }) }
  let!(:broadcast) { create(:conversation, inbox: inbox, account: inbox.account, additional_attributes: { telegram_channel: true }) }

  it 'hides stored groups and channels without deleting conversations or private messages' do
    result = described_class.perform(inbox.conversations)
    expect(result).to contain_exactly(direct)
    expect(inbox.conversations.count).to eq(3)
    channel.update!(hide_groups: false)
    expect(described_class.perform(inbox.conversations)).to contain_exactly(direct, group)
    channel.update!(hide_channels: false)
    expect(described_class.perform(inbox.conversations)).to contain_exactly(direct, group, broadcast)
  end

  it 'keeps hiding separate from ignoring future messages' do
    channel.update!(hide_groups: false, hide_channels: false)
    expect(channel).to be_ignore_groups
    expect(channel).to be_ignore_channels
    expect(described_class.perform(inbox.conversations)).to contain_exactly(direct, group, broadcast)
  end

  it 'does not hide another inbox or account based on matching attributes' do
    other = create(:inbox)
    other_group = create(:conversation, inbox: other, account: other.account, additional_attributes: { telegram_group: true })
    expect(described_class.perform(other.conversations)).to contain_exactly(other_group)
  end
end
