namespace :whatsmeow do
  desc 'Queue profile picture sync for contacts in Whatsmeow inboxes'
  task sync_profile_pictures: :environment do
    force = ActiveModel::Type::Boolean.new.cast(ENV.fetch('FORCE', false))
    queued = 0

    Inbox.includes(:channel, :contact_inboxes).where(channel_type: 'Channel::Whatsmeow').find_each do |inbox|
      inbox.contact_inboxes.find_each do |contact_inbox|
        Whatsmeow::ProfilePictureSyncJob.perform_later(contact_inbox.contact_id, inbox.id, contact_inbox.source_id, force: force)
        queued += 1
      end
    end

    puts "Queued #{queued} Whatsmeow profile picture sync jobs."
  end
end
