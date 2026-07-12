class Whatsmeow::ContactSyncListener < BaseListener
  def contact_created(event)
    contact = event.data[:contact]
    enqueue_sync(contact.account_id, contact.push_event_data)
  end

  def contact_updated(event)
    changes = event.data[:changed_attributes].to_h.stringify_keys
    return if changes.keys.intersection(%w[name phone_number]).blank?

    contact = event.data[:contact]
    previous_phone_number = changes.dig('phone_number', 0)
    enqueue_sync(contact.account_id, contact.push_event_data, previous_phone_number)
  end

  def contact_deleted(event)
    contact_data = event.data[:contact_data].symbolize_keys
    enqueue_sync(contact_data[:account_id], contact_data, nil, true)
  end

  private

  def enqueue_sync(account_id, contact_data, previous_phone_number = nil, deleted = false)
    Whatsmeow::ContactSyncJob.perform_later(account_id, contact_data, previous_phone_number, deleted)
  end
end
