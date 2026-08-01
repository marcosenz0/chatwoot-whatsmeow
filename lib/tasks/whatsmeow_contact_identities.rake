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
         "#{stats[:inboxes_skipped]} inboxes skipped, #{stats[:own_identities_skipped]} own identities skipped."
  end
end
