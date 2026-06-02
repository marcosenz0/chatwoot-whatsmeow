namespace :whatsmeow do
  desc 'Sync profile pictures for contacts in Whatsmeow inboxes'
  task sync_profile_pictures: :environment do
    force = ActiveModel::Type::Boolean.new.cast(ENV.fetch('FORCE', false))
    inline = ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::AsyncAdapter) ||
             ActiveModel::Type::Boolean.new.cast(ENV.fetch('INLINE', false))
    synced = 0

    Inbox.includes(:channel, :contact_inboxes).where(channel_type: 'Channel::Whatsmeow').find_each do |inbox|
      inbox.contact_inboxes.find_each do |contact_inbox|
        if inline
          Whatsmeow::ProfilePictureSyncJob.perform_now(contact_inbox.contact_id, inbox.id, contact_inbox.source_id, force: force)
        else
          Whatsmeow::ProfilePictureSyncJob.perform_later(contact_inbox.contact_id, inbox.id, contact_inbox.source_id, force: force)
        end
        synced += 1
      end
    end

    action = inline ? 'Synced' : 'Queued'
    puts "#{action} #{synced} Whatsmeow profile picture sync jobs."
  end
end
