class Whatsmeow::FullContactSyncJob < ApplicationJob
  queue_as :default

  retry_on Whatsmeow::SessionClient::Error, wait: :polynomially_longer, attempts: 5

  def perform(inbox_id)
    inbox = Inbox.find_by(id: inbox_id, channel_type: 'Channel::Whatsmeow')
    return if inbox.blank?

    Whatsmeow::SessionClient.new(inbox: inbox).sync_contacts(account_contacts(inbox.account))
  end

  private

  def account_contacts(account)
    account.contacts.where.not(phone_number: [nil, '']).pluck(:phone_number, :name).filter_map do |phone_number, name|
      phone = phone_number.to_s.delete('^0-9')
      next unless phone.match?(/\A[1-9]\d{5,14}\z/)

      { jid: "#{phone}@s.whatsapp.net", name: name.presence || phone_number }
    end
  end
end
