class Whatsapp::CloudTemplateService
  class Error < StandardError; end

  pattr_initialize [:inbox!]

  def list(sync: false)
    sync! if sync
    {
      templates: channel.message_templates || [],
      last_updated_at: channel.message_templates_last_updated
    }
  end

  def sync!
    ensure_official_cloud_inbox!
    channel.sync_templates
    channel.reload.message_templates || []
  rescue Whatsapp::Providers::WhatsappCloudService::TemplateSyncError => e
    raise Error, e.message
  end

  def create!(attributes)
    ensure_official_cloud_inbox!
    payload = build_payload(attributes.with_indifferent_access)
    response = HTTParty.post(
      provider.template_management_path,
      headers: provider.api_headers,
      body: payload.to_json
    )
    raise Error, response_error(response) unless response.success?

    sync!
    response.parsed_response
  end

  def delete!(name)
    ensure_official_cloud_inbox!
    raise Error, 'Template name is required' if name.blank?

    response = HTTParty.delete(
      "#{provider.template_management_path}?name=#{ERB::Util.url_encode(name)}",
      headers: provider.api_headers
    )
    raise Error, response_error(response) unless response.success?

    sync!
    response.parsed_response
  end

  private

  delegate :channel, to: :inbox

  def provider
    @provider ||= channel.provider_service
  end

  def ensure_official_cloud_inbox!
    return if inbox.channel_type == 'Channel::Whatsapp' && channel.provider == 'whatsapp_cloud'

    raise Error, 'Official WhatsApp Cloud API inbox required'
  end

  def build_payload(attributes)
    name = attributes[:name].to_s.downcase.strip.gsub(/[^a-z0-9_]+/, '_')
    language = attributes[:language].presence || 'pt_BR'
    category = attributes[:category].to_s.upcase
    components = Array(attributes[:components]).map { |component| sanitize_component(component) }

    validate_template_payload!(name, category, components)

    {
      name: name,
      language: language,
      category: category,
      allow_category_change: true,
      components: components
    }
  end

  def validate_template_payload!(name, category, components)
    raise Error, 'Template name is required' if name.blank?
    raise Error, 'Template category is invalid' unless %w[MARKETING UTILITY AUTHENTICATION].include?(category)
    raise Error, 'Template body is required' unless components.any? { |component| component[:type] == 'BODY' && component[:text].present? }
  end

  def sanitize_component(component)
    component = component.with_indifferent_access
    type = component[:type].to_s.upcase
    sanitized = { type: type }
    sanitized[:format] = component[:format].to_s.upcase if component[:format].present?
    sanitized[:text] = component[:text].to_s if component[:text].present?
    sanitized[:example] = component[:example].to_h if component[:example].present?
    sanitized[:buttons] = sanitize_buttons(component[:buttons]) if type == 'BUTTONS'
    sanitized.compact
  end

  def sanitize_buttons(buttons)
    Array(buttons).first(3).map do |button|
      button = button.with_indifferent_access
      sanitized = {
        type: button[:type].to_s.upcase,
        text: button[:text].to_s
      }
      sanitized[:url] = button[:url].to_s if button[:url].present?
      sanitized[:phone_number] = button[:phone_number].to_s if button[:phone_number].present?
      sanitized.compact
    end
  end

  def response_error(response)
    response.parsed_response&.dig('error', 'error_user_msg').presence ||
      response.parsed_response&.dig('error', 'message').presence ||
      'Meta rejected the template request'
  end
end
