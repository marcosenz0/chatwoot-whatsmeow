namespace :whatsmeow do
  desc 'Split contacts corrupted by the Whatsmeow identity incident; dry-run unless APPLY=true'
  task repair_contact_identity_incident: :environment do
    account_id = ENV.fetch('ACCOUNT_ID', '').presence
    abort 'ACCOUNT_ID is required.' if account_id.blank?

    apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch('APPLY', false))
    root_contact_id = ENV.fetch('ROOT_CONTACT_ID', '').presence
    if apply && (root_contact_id.blank? || ENV.fetch('CONFIRM', '') != 'split-corrupted-whatsmeow-contacts')
      abort 'Set ROOT_CONTACT_ID and CONFIRM=split-corrupted-whatsmeow-contacts together with APPLY=true.'
    end

    report = Whatsmeow::ContactIdentityIncidentRepairService.new(
      account: Account.find(account_id),
      inbox_id: ENV.fetch('INBOX_ID', '').presence,
      contact_ids: [root_contact_id].compact,
      apply: apply,
      snapshot_dir: ENV.fetch('SNAPSHOT_DIR', '').presence
    ).perform

    puts JSON.pretty_generate(report)
  end
end
