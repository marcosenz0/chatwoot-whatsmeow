class Whatsmeow::StatusContactCleanupJob < ApplicationJob
  queue_as :default

  retry_on Whatsmeow::SessionClient::Error, wait: :polynomially_longer, attempts: 5

  def perform(inbox_id)
    inbox = Inbox.find_by(id: inbox_id, channel_type: 'Channel::Whatsmeow')
    return if inbox.blank?

    Whatsmeow::SessionClient.new(inbox: inbox).sync_contacts(cleanup_entries(inbox.account))
  end

  private

  def cleanup_entries(account)
    account.contacts.where.not(phone_number: [nil, '']).pluck(:phone_number).filter_map do |phone_number|
      phone = phone_number.to_s.delete('^0-9')
      next unless phone.match?(/\A[1-9]\d{5,14}\z/)

      { jid: "#{phone}@s.whatsapp.net", deleted: true }
    end
  end
end
