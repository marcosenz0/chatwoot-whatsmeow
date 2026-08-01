class Whatsapp::CloudWebhookPayloadSplitter
  EVENT_COLLECTIONS = %i[messages statuses message_echoes calls].freeze

  pattr_initialize [:params!]

  def perform
    change_payloads.flat_map do |payload|
      root = payload.with_indifferent_access
      entry = root[:entry].first.with_indifferent_access
      change = entry[:changes].first.with_indifferent_access
      split_change(root, entry, change)
    end
  end

  def change_payloads
    root = params.with_indifferent_access
    return [] unless root[:object] == 'whatsapp_business_account'

    Array(root[:entry]).flat_map do |entry|
      normalized_entry = entry.with_indifferent_access
      Array(normalized_entry[:changes]).map do |change|
        normalized_change = change.with_indifferent_access
        value = normalized_change[:value].to_h.with_indifferent_access
        single_change_payload(root, normalized_entry, normalized_change, value)
      end
    end
  end

  private

  def split_change(root, entry, change)
    value = change[:value].to_h.with_indifferent_access
    event_collections = EVENT_COLLECTIONS.filter_map do |key|
      records = Array(value[key])
      [key, records] if records.present?
    end
    return [single_change_payload(root, entry, change, value)] if event_collections.empty?

    context = { root: root, entry: entry, change: change, value: value }
    event_collections.flat_map do |key, records|
      records.map { |record| event_payload(context, key, record) }
    end
  end

  def event_payload(context, collection, record)
    event_value = context[:value].except(*EVENT_COLLECTIONS)
    event_value[collection] = [record]
    event_value[:contacts] = matching_contacts(context[:value][:contacts], record, collection) if context[:value][:contacts].present?
    single_change_payload(context[:root], context[:entry], context[:change], event_value)
  end

  def single_change_payload(root, entry, change, value)
    event_change = change.deep_dup
    event_change[:value] = value
    event_entry = entry.deep_dup
    event_entry[:changes] = [event_change]
    root.deep_dup.merge(entry: [event_entry])
  end

  def matching_contacts(contacts, event, collection)
    contacts = Array(contacts).map(&:with_indifferent_access)
    identifiers = event_identifiers(event.with_indifferent_access, collection)
    match = contacts.find do |contact|
      contact_identifiers = [contact[:wa_id], contact[:user_id], contact[:parent_user_id]].compact_blank.map(&:to_s)
      contact_identifiers.intersect?(identifiers)
    end
    [match || contacts.first]
  end

  def event_identifiers(event, collection)
    keys = case collection
           when :message_echoes
             %i[to to_user_id to_parent_user_id]
           when :statuses
             %i[recipient_id recipient_user_id recipient_parent_user_id]
           else
             %i[from from_user_id from_parent_user_id]
           end
    keys.filter_map { |key| event[key].presence&.to_s }
  end
end
