module Whatsmeow::StatusPayloadable
  extend ActiveSupport::Concern

  private

  def status_payload(status, viewed_status_ids, viewer_counts = {})
    status_inbox = owned_status_inbox(status)
    core_status_payload(status, status_inbox)
      .merge(publication_payload(status))
      .merge(status_activity_payload(status, viewed_status_ids, viewer_counts))
  end

  def core_status_payload(status, status_inbox)
    {
      id: status.id,
      source_id: status.source_id,
      inbox_id: status_inbox&.id || status.inbox_id,
      inbox_name: status_inbox&.name,
      contact: contact_payload(status.contact),
      sender_jid: status.sender_jid,
      sender_name: status.sender_name,
      sender_phone: status.sender_phone,
      from_me: status_inbox.present?,
      record_from_me: status.from_me,
      status_type: status.status_type,
      content: status.content,
      media: media_payload(status),
      metadata: status.metadata
    }
  end

  def publication_payload(status)
    {
      publication_id: status.publication_id,
      publication_position: status.publication_position,
      publication_state: status.publication_state,
      publish_attempts: status.publish_attempts,
      last_error: status.last_error,
      next_attempt_at: status.next_attempt_at&.to_i,
      session_key: status.session_key
    }
  end

  def status_activity_payload(status, viewed_status_ids, viewer_counts)
    {
      posted_at: status.posted_at.to_i,
      expires_at: status.expires_at.to_i,
      viewed: status.metadata['status_already_viewed'] || viewed_status_ids[status.id] || false,
      viewer_count: status.from_me? ? viewer_counts.fetch(status.id, 0) : 0,
      created_by: status.created_by&.name
    }
  end

  def owned_status_inbox(status)
    return status.inbox if status.from_me?

    account_whatsmeow_inboxes_by_phone[normalized_phone(status.sender_phone.presence || status.sender_jid)]
  end

  def account_whatsmeow_inboxes_by_phone
    @account_whatsmeow_inboxes_by_phone ||= Current.account.inboxes.includes(:channel).filter_map do |inbox|
      next unless inbox.channel_type == 'Channel::Whatsmeow'

      phone = normalized_phone(inbox.channel.phone_number)
      [phone, inbox] if phone.present?
    end.to_h
  end

  def normalized_phone(value)
    value.to_s.split('@').first.split(':').first.delete('^0-9')
  end

  def status_viewer_counts(statuses)
    WhatsmeowStatusViewer
      .where(whatsmeow_status_id: statuses.select(&:from_me?).map(&:id))
      .group_by(&:whatsmeow_status_id)
      .transform_values { |viewers| viewers.uniq(&:identity_key).size }
  end

  def status_viewer_payload(viewer, status)
    {
      id: viewer.id,
      status_id: viewer.whatsmeow_status_id,
      inbox_id: status.inbox_id,
      inbox_name: status.inbox.name,
      viewer_jid: viewer.viewer_jid,
      viewer_name: viewer.viewer_name,
      viewer_phone: viewer.viewer_phone,
      contact: contact_payload(viewer.contact),
      viewed_at: viewer.viewed_at.to_i
    }
  end

  def contact_payload(contact)
    return if contact.blank?

    {
      id: contact.id,
      name: contact.name,
      phone_number: contact.phone_number,
      avatar_url: contact.avatar_url
    }
  end

  def media_payload(status)
    return unless status.media.attached?

    {
      url: url_for(status.media),
      content_type: status.media.content_type,
      filename: status.media.filename.to_s,
      byte_size: status.media.byte_size
    }
  end
end
