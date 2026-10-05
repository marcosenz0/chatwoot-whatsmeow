FactoryBot.define do
  factory :channel_telegram_personal, class: 'Channel::TelegramPersonal' do
    account
    sequence(:phone_number) { |n| "+1555000#{n.to_s.rjust(4, '0')}" }

    after(:create) do |channel|
      create(:inbox, channel: channel, account: channel.account)
    end
  end
end
