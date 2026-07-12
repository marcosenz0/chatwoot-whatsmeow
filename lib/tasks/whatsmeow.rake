namespace :whatsmeow do
  desc 'Reconcile Whatsmeow LID contacts with phone identities; use APPLY=true to persist changes'
  task reconcile_contact_identities: :environment do
    account_id = ENV.fetch('ACCOUNT_ID', '').presence
    abort 'ACCOUNT_ID is required.' if account_id.blank?

    apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch('APPLY', false))
    stats = Whatsmeow::ContactIdentityReconciliationService.new(
      account: Account.find(account_id),
      dry_run: !apply
    ).perform

    mode = apply ? 'Applied' : 'Dry run'
    puts "#{mode}: #{stats[:resolved]} identities resolved, #{stats[:unresolved]} unresolved, " \
         "#{stats[:contacts_merged]} duplicate contacts, #{stats[:conversation_groups_merged]} open conversation groups, " \
         "#{stats[:inboxes_skipped]} inboxes skipped."
  end

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

  desc 'Purge old Whatsmeow media attachments; use DRY_RUN=true to only report'
  task purge_old_attachments: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', false))

    Whatsmeow::PurgeOldAttachmentsJob.perform_now(dry_run: dry_run)
  end
end
