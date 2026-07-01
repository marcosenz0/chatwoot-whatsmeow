FactoryBot.define do
  factory :channel_whatsmeow, class: 'Channel::Whatsmeow' do
    account
    sequence(:phone_number) { |n| "+55639118#{n.to_s.rjust(4, '0')}" }
    status { 'connected' }

    after(:create) do |channel_whatsmeow|
      create(:inbox, channel: channel_whatsmeow, account: channel_whatsmeow.account)
    end
  end
end
