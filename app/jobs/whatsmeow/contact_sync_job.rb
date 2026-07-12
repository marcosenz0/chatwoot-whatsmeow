class Whatsmeow::ContactSyncJob < ApplicationJob
  queue_as :default

  retry_on Whatsmeow::SessionClient::Error, wait: :polynomially_longer, attempts: 5

  def perform(account_id, contact_data, previous_phone_number = nil, deleted: false)
    contacts = sync_entries(contact_data.symbolize_keys, previous_phone_number, deleted)
    return if contacts.blank?

    errors = []
    Account.find(account_id).inboxes.where(channel_type: 'Channel::Whatsmeow').find_each do |inbox|
      next unless inbox.channel.status == 'connected'

      Whatsmeow::SessionClient.new(inbox: inbox).sync_contacts(contacts)
    rescue Whatsmeow::SessionClient::Error => e
      errors << "#{inbox.id}: #{e.message}"
    end
    raise Whatsmeow::SessionClient::Error, errors.join(', ') if errors.any?
  end

  private

  def sync_entries(contact, previous_phone_number, deleted)
    entries = []
    previous_jid = jid_for(previous_phone_number)
    current_jid = jid_for(contact[:phone_number])

    entries << { jid: previous_jid, deleted: true } if previous_jid.present? && previous_jid != current_jid
    if deleted
      entries << { jid: current_jid, deleted: true } if current_jid.present?
    elsif current_jid.present?
      entries << { jid: current_jid, name: contact[:name].presence || contact[:phone_number] }
    end
    entries
  end

  def jid_for(phone_number)
    phone = phone_number.to_s.delete('^0-9')
    return if phone.blank? || !phone.match?(/\A[1-9]\d{5,14}\z/)

    "#{phone}@s.whatsapp.net"
  end
end
