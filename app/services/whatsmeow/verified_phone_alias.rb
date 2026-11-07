class Whatsmeow::VerifiedPhoneAlias
  pattr_initialize [:inbox!, :phone_number!, :peer_lid!]

  def perform
    return unless phone_number.to_s.match?(/\A\+55[1-9]\d{9,10}\z/)

    digits = phone_number.delete_prefix('+')
    alternate = Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.variants(digits).find { |variant| variant != digits }
    return if alternate.blank? || alternate == inbox.channel.phone_number.to_s.delete('^0-9')

    source_id = "#{alternate}@s.whatsapp.net"
    contact_inboxes = inbox.contact_inboxes.where(source_id: source_id).select(:id)
    return unless inbox.conversations.where(contact_inbox_id: contact_inboxes).where.not(status: :resolved).exists?

    peer_jid = peer_lid.to_s.match?(/\A[1-9]\d+@lid\z/) ? peer_lid : registered_jid(phone_number)
    source_id if peer_jid.present? && registered_jid("+#{alternate}") == peer_jid
  rescue Whatsmeow::SessionClient::Error => e
    Rails.logger.warn("Whatsmeow: Phone alias verification unavailable in inbox #{inbox.id}: #{e.class}")
    nil
  end

  private

  def registered_jid(phone)
    @client ||= Whatsmeow::SessionClient.new(inbox: inbox)
    result = @client.check_number(phone)
    jid = result['jid'].to_s
    jid if result['is_on_whatsapp'] == true && jid.match?(/\A[1-9]\d+@(lid|s\.whatsapp\.net)\z/)
  end
end

