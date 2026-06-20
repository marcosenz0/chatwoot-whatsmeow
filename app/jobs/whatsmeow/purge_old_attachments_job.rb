class Whatsmeow::PurgeOldAttachmentsJob < ApplicationJob
  queue_as :housekeeping

  DEFAULT_RETENTION_DAYS = 30
  DEFAULT_BATCH_SIZE = 500

  def perform(dry_run: false)
    return if retention_days <= 0

    purged_count = 0
    purged_bytes = 0

    old_whatsmeow_attachments.limit(batch_size).each do |attachment|
      byte_size = attachment.file.blob.byte_size
      purged_count += 1
      purged_bytes += byte_size

      next if dry_run

      attachment.file.purge
    rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError => e
      Rails.logger.warn(
        "Whatsmeow attachment #{attachment.id} could not be purged: #{e.message}"
      )
    end

    Rails.logger.info(
      "Whatsmeow attachment retention #{dry_run ? 'would purge' : 'purged'} #{purged_count} files " \
      "(#{purged_bytes} bytes) older than #{retention_days} days"
    )
  end

  private

  def retention_days
    @retention_days ||= ENV.fetch('WHATSMEOW_ATTACHMENT_RETENTION_DAYS', DEFAULT_RETENTION_DAYS).to_i
  end

  def batch_size
    @batch_size ||= [ENV.fetch('WHATSMEOW_ATTACHMENT_RETENTION_BATCH_SIZE', DEFAULT_BATCH_SIZE).to_i, 1].max
  end

  def cutoff
    retention_days.days.ago
  end

  def old_whatsmeow_attachments
    Attachment.joins(message: :inbox)
              .joins(:file_attachment)
              .where(inboxes: { channel_type: 'Channel::Whatsmeow' })
              .where('messages.created_at < ?', cutoff)
              .where(file_type: media_file_types)
              .where(
                "COALESCE(attachments.meta ->> 'whatsmeow_sticker', " \
                "attachments.meta ->> 'whatsmeowSticker', 'false') != 'true'"
              )
              .order(:id)
  end

  def media_file_types
    Attachment.file_types.values_at('image', 'audio', 'video', 'file')
  end
end
