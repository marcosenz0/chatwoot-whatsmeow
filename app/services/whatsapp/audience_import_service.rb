require 'set'

class Whatsapp::AudienceImportService
  class Error < StandardError; end

  MAX_CONTACTS = 5000
  DEFAULT_COUNTRY_CODE = '55'

  def initialize(account:, inbox:, contacts:, consent_confirmed:, default_country_code: DEFAULT_COUNTRY_CODE)
    @account = account
    @inbox = inbox
    @contacts = Array(contacts)
    @consent_confirmed = ActiveModel::Type::Boolean.new.cast(consent_confirmed)
    @default_country_code = default_country_code.to_s.gsub(/\D/, '').presence || DEFAULT_COUNTRY_CODE
  end

  def perform
    validate!

    result = initial_result
    seen_phone_numbers = Set.new

    contacts.each_with_index do |attributes, index|
      import_contact(attributes.to_h.with_indifferent_access, index, result, seen_phone_numbers)
    end

    result[:contact_ids].uniq!
    result
  end

  private

  attr_reader :account, :inbox, :contacts, :consent_confirmed, :default_country_code

  def validate!
    raise Error, 'Confirme que os contatos autorizaram mensagens pelo WhatsApp' unless consent_confirmed
    raise Error, 'Adicione pelo menos um contato' if contacts.empty?
    raise Error, "O limite por importação é de #{MAX_CONTACTS} contatos" if contacts.length > MAX_CONTACTS
  end

  def initial_result
    {
      total: contacts.length,
      imported: 0,
      created: 0,
      updated: 0,
      duplicates: 0,
      ignored: 0,
      invalid: 0,
      contact_ids: [],
      issues: []
    }
  end

  def import_contact(attributes, index, result, seen_phone_numbers)
    phone_number = normalize_phone_number(attributes[:phone_number])
    return add_issue(result, index, attributes[:phone_number], 'Número inválido') if phone_number.blank?

    unless seen_phone_numbers.add?(phone_number)
      result[:duplicates] += 1
      return
    end

    contact = account.contacts.find_or_initialize_by(phone_number: phone_number)
    was_new = contact.new_record?
    return add_ignored(result, index, phone_number, 'Contato bloqueado') if contact.blocked?
    return add_ignored(result, index, phone_number, 'Contato marcou que não deseja receber mensagens') if whatsapp_opted_out?(contact)

    assign_contact_attributes(contact, attributes, phone_number)
    contact.save!
    ContactInboxBuilder.new(contact: contact, inbox: inbox).perform

    result[:contact_ids] << contact.id
    result[:imported] += 1
    result[was_new ? :created : :updated] += 1
  rescue ActiveRecord::RecordInvalid => e
    add_issue(result, index, attributes[:phone_number], e.record.errors.full_messages.to_sentence)
  rescue StandardError => e
    add_issue(result, index, attributes[:phone_number], e.message)
  end

  def assign_contact_attributes(contact, attributes, phone_number)
    contact.name = attributes[:name].to_s.strip.presence || phone_number if contact.name.blank?
    contact.additional_attributes = contact.additional_attributes.merge(
      attributes[:company_name].present? ? { 'company_name' => attributes[:company_name].to_s.strip } : {}
    )
    contact.custom_attributes = contact.custom_attributes.merge(
      'whatsapp_opt_in' => true,
      'whatsapp_opt_in_at' => Time.current.iso8601,
      'whatsapp_opt_in_source' => 'whatsapp_cloud_studio_import'
    )
  end

  def normalize_phone_number(value)
    raw_value = value.to_s.strip
    return if raw_value.blank?

    explicit_country_code = raw_value.start_with?('+', '00')
    digits = raw_value.gsub(/\D/, '')
    digits = digits.delete_prefix('00') if raw_value.start_with?('00')

    unless explicit_country_code
      digits = digits.delete_prefix('0') if digits.start_with?('0') && digits.length.in?([11, 12])
      digits = "#{default_country_code}#{digits}" if digits.length.in?([10, 11])
    end

    return unless digits.match?(/\A[1-9]\d{9,14}\z/)

    "+#{digits}"
  end

  def whatsapp_opted_out?(contact)
    ActiveModel::Type::Boolean.new.cast(contact.custom_attributes['whatsapp_opt_out']) ||
      contact.label_list.any? { |label| label.to_s.downcase.in?(%w[whatsapp_opt_out do_not_contact optout]) }
  end

  def add_issue(result, index, phone_number, reason)
    result[:invalid] += 1
    result[:issues] << issue_payload(index, phone_number, reason)
  end

  def add_ignored(result, index, phone_number, reason)
    result[:ignored] += 1
    result[:issues] << issue_payload(index, phone_number, reason)
  end

  def issue_payload(index, phone_number, reason)
    { row: index + 1, phone_number: phone_number.to_s, reason: reason }
  end
end
