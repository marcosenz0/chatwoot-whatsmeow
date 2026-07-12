class Whatsmeow::ContactIdentityResolver
  pattr_initialize [:inbox!, :source_ids!, :phone_number!, :contact_attributes!]

  def perform
    raise ArgumentError, 'Missing WhatsApp phone identity' if normalized_phone_number.blank?

    ActiveRecord::Base.transaction { resolve_identity }
  end

  private

  def resolve_identity
    contact_inboxes = inbox.contact_inboxes.includes(:contact).where(source_id: lookup_source_ids).to_a
    contacts, phone_contact = identity_contacts(contact_inboxes)
    canonical_contact = canonical_contact_for(contact_inboxes, contacts, phone_contact)
    preferred_name = preferred_contact_name(contacts)
    merge_contacts(canonical_contact, contacts)
    update_contact_identity(canonical_contact, preferred_name)
    resolve_contact_inbox(canonical_contact)
  end

  def identity_contacts(contact_inboxes)
    phone_contact = inbox.account.contacts.find_by(phone_number: normalized_phone_number)
    contacts = (contact_inboxes.map(&:contact) + [phone_contact]).compact.uniq(&:id)
    [contacts, phone_contact]
  end

  def canonical_contact_for(contact_inboxes, contacts, phone_contact)
    phone_contact || phone_contact_inbox(contact_inboxes)&.contact || contacts.first || create_contact
  end

  def resolve_contact_inbox(contact)
    contact_inboxes = ensure_contact_inboxes(contact)
    canonical_contact_inbox = phone_contact_inbox(contact_inboxes) || contact_inboxes.first
    merge_open_conversations(contact, canonical_contact_inbox)
    canonical_contact_inbox
  end

  def normalized_phone_number
    @normalized_phone_number ||= begin
      value = phone_number.to_s.strip
      value if value.match?(/\A\+[1-9]\d{9,14}\z/)
    end
  end

  def phone_source_id
    @phone_source_id ||= "#{normalized_phone_number.delete('+')}@s.whatsapp.net"
  end

  def normalized_source_ids
    @normalized_source_ids ||= ([phone_source_id] + Array(source_ids)).filter_map do |source_id|
      normalize_source_id(source_id)
    end.uniq
  end

  def lookup_source_ids
    @lookup_source_ids ||= (normalized_source_ids + Array(source_ids).compact_blank.map(&:to_s)).uniq
  end

  def normalize_source_id(source_id)
    value = source_id.to_s.strip
    return if value.blank? || value.exclude?('@')

    user, server = value.split('@', 2)
    return unless %w[lid s.whatsapp.net].include?(server)

    user = user.split(':').first
    "#{user}@#{server}" if user.match?(/\A[1-9]\d+\z/)
  end

  def phone_contact_inbox(contact_inboxes)
    contact_inboxes.find { |contact_inbox| contact_inbox.source_id == phone_source_id }
  end

  def create_contact
    inbox.account.contacts.create!(
      name: normalized_phone_number,
      phone_number: normalized_phone_number,
      additional_attributes: contact_attributes[:additional_attributes]
    )
  end

  def merge_contacts(canonical_contact, contacts)
    contacts.reject { |contact| contact.id == canonical_contact.id }.each do |duplicate_contact|
      preserve_avatar(canonical_contact, duplicate_contact)
      # These relationships are moved in bulk before ContactMergeAction destroys the duplicate contact.
      # rubocop:disable Rails/SkipsModelValidations
      CsatSurveyResponse.where(contact_id: duplicate_contact.id).update_all(contact_id: canonical_contact.id)
      WhatsmeowStatus.where(contact_id: duplicate_contact.id).update_all(contact_id: canonical_contact.id)
      # rubocop:enable Rails/SkipsModelValidations
      ContactMergeAction.new(
        account: inbox.account,
        base_contact: canonical_contact,
        mergee_contact: duplicate_contact
      ).perform
      canonical_contact.reload
    end
  end

  def preserve_avatar(canonical_contact, duplicate_contact)
    return if canonical_contact.avatar.attached? || !duplicate_contact.avatar.attached?

    canonical_contact.avatar.attach(duplicate_contact.avatar.blob)
  end

  def preferred_contact_name(contacts)
    contacts.filter_map(&:name).find { |name| human_name?(name) }
  end

  def human_name?(name)
    value = name.to_s.strip
    return false if value.blank? || value == normalized_phone_number
    return false if value.match?(/\A\+?\d+\z/)

    !value.match?(/@(lid|s\.whatsapp\.net|g\.us)\z/i)
  end

  def update_contact_identity(contact, preferred_name)
    attributes = { phone_number: normalized_phone_number }
    attributes[:name] = preferred_name.presence || normalized_phone_number unless human_name?(contact.name)
    additional_attributes = contact_attributes[:additional_attributes]
    if additional_attributes.present?
      attributes[:additional_attributes] = (contact.additional_attributes || {}).merge(additional_attributes.stringify_keys)
    end
    contact.update!(attributes)
  end

  def ensure_contact_inboxes(contact)
    normalized_source_ids.map do |source_id|
      contact_inbox = inbox.contact_inboxes.find_by(source_id: source_id)
      if contact_inbox
        contact_inbox.update!(contact: contact) if contact_inbox.contact_id != contact.id
        contact_inbox
      else
        ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: source_id).perform
      end
    end
  end

  def merge_open_conversations(contact, contact_inbox)
    Whatsmeow::OpenConversationMergeService.new(
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      source_ids: lookup_source_ids
    ).perform
  end
end
