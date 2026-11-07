class Whatsmeow::VerifiedPhoneAlias
  pattr_initialize [:inbox!, :phone_number!, :peer_lid!]

  def perform
    source_id = active_alternate_source_id
    return if source_id.blank?

    peer_jid = peer_lid.to_s.match?(/\A[1-9]\d+@lid\z/) ? peer_lid : registered_jid(phone_number)
    source_id if peer_jid.present? && registered_jid("+#{source_id.split('@').first}") == peer_jid
  rescue Whatsmeow::SessionClient::Error => e
    Rails.logger.warn("Whatsmeow: Phone alias verification unavailable in inbox #{inbox.id}: #{e.class}")
    nil
  end

  private

  def active_alternate_source_id
    return unless phone_number.to_s.match?(/\A\+55[1-9]\d{9,10}\z/)

    digits = phone_number.delete_prefix('+')
    alternate = Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.variants(digits).find { |variant| variant != digits }
    owner = inbox.channel.phone_number.to_s.delete('^0-9')
    return if alternate.blank? || [digits, alternate].include?(owner)

    source_id = "#{alternate}@s.whatsapp.net"
    contact_inboxes = inbox.contact_inboxes.where(source_id: source_id).select(:id)
    source_id if inbox.conversations.where(contact_inbox_id: contact_inboxes).where.not(status: :resolved).exists?
  end

  def registered_jid(phone)
    @client ||= Whatsmeow::SessionClient.new(inbox: inbox)
    result = @client.check_number(phone)
    jid = result['jid'].to_s
    jid if result['is_on_whatsapp'] == true && jid.match?(/\A[1-9]\d+@(lid|s\.whatsapp\.net)\z/)
  end
end

