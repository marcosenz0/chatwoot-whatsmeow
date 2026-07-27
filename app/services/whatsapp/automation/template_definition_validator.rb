class Whatsapp::Automation::TemplateDefinitionValidator
  SUPPORTED_COMPONENT_TYPES = %w[HEADER BODY FOOTER BUTTONS].freeze
  SUPPORTED_HEADER_FORMATS = ['', 'TEXT', 'IMAGE', 'VIDEO', 'DOCUMENT'].freeze
  SUPPORTED_BUTTON_TYPES = %w[QUICK_REPLY URL PHONE_NUMBER COPY_CODE].freeze
  MEDIA_HEADER_FORMATS = %w[IMAGE VIDEO DOCUMENT].freeze

  def initialize(node_id:, config:, template:)
    @node_id = node_id
    @config = config.with_indifferent_access
    @template = template.with_indifferent_access
    @errors = []
  end

  def validate
    validate_supported_template
    validate_header_parameters
    validate_body_parameters
    validate_button_parameters
    errors
  end

  private

  attr_reader :node_id, :config, :template, :errors

  def components
    @components ||= Array(template[:components]).map(&:with_indifferent_access)
  end

  def component(type)
    components.find { |record| record[:type].to_s.upcase == type }
  end

  def processed_params
    @processed_params ||= config[:processed_params].to_h.with_indifferent_access
  end

  def validate_supported_template
    return unless unsupported_template?

    errors << "template node #{node_id} uses unsupported template components"
  end

  def unsupported_template?
    template[:category].to_s.casecmp?('AUTHENTICATION') ||
      component('BODY').blank? ||
      components.any? { |record| SUPPORTED_COMPONENT_TYPES.exclude?(record[:type].to_s.upcase) } ||
      unsupported_header? ||
      template_buttons.any? { |button| SUPPORTED_BUTTON_TYPES.exclude?(button[:type].to_s.upcase) }
  end

  def unsupported_header?
    header = component('HEADER')
    header.present? && SUPPORTED_HEADER_FORMATS.exclude?(header[:format].to_s.upcase)
  end

  def validate_header_parameters
    header = component('HEADER')
    return if header.blank?

    format = header[:format].to_s.upcase
    if MEDIA_HEADER_FORMATS.include?(format)
      validate_media_header(format)
      return
    end

    validate_text_variables('header', header[:text], processed_params[:header])
  end

  def validate_body_parameters
    body = component('BODY')
    validate_text_variables('body', body&.dig(:text), processed_params[:body])
  end

  def validate_media_header(format)
    header_params = processed_params[:header].to_h.with_indifferent_access
    media_url = header_params[:media_url]
    errors << "template node #{node_id} needs a valid header media URL" unless valid_media_url?(media_url)
    return if header_params[:media_type].to_s.casecmp?(format.downcase)

    errors << "template node #{node_id} needs header media type #{format.downcase}"
  end

  def valid_media_url?(value)
    uri = URI.parse(value.to_s)
    uri.host.present? && %w[http https].include?(uri.scheme)
  rescue URI::InvalidURIError
    false
  end

  def validate_text_variables(section, text, values)
    required = variable_keys(text)
    return if required.empty?

    values = values.to_h.with_indifferent_access
    missing = required.reject { |key| values[key].present? }
    errors << "template node #{node_id} needs values for #{section} variables #{missing.join(', ')}" if missing.any?
  end

  def validate_button_parameters
    missing = template_buttons.filter_map.with_index do |button, index|
      type = button[:type].to_s.upcase
      next unless button_parameter_required?(button, type)

      index unless valid_button_parameter?(type, index)
    end
    errors << "template node #{node_id} needs values for button parameters #{missing.join(', ')}" if missing.any?
  end

  def button_parameter_required?(button, type)
    return variable_keys(button[:url]).any? if type == 'URL'

    %w[QUICK_REPLY COPY_CODE].include?(type)
  end

  def template_buttons
    @template_buttons ||= Array(component('BUTTONS')&.dig(:buttons)).map(&:with_indifferent_access)
  end

  def valid_button_parameter?(type, index)
    parameter = button_parameter(type, index)
    return false if parameter.blank?

    valid_button_parameter_value?(type, parameter)
  end

  def button_parameter(type, index)
    Array(processed_params[:buttons]).map(&:with_indifferent_access).find do |record|
      record[:index].present? && record[:type].to_s.casecmp?(type.downcase) && record[:index].to_i == index
    end
  end

  def valid_button_parameter_value?(type, parameter)
    case type
    when 'QUICK_REPLY'
      parameter[:payload].present?
    when 'COPY_CODE'
      parameter[:parameter].to_s.length.between?(1, 15)
    else
      parameter[:parameter].present?
    end
  end

  def variable_keys(text)
    text.to_s.scan(/\{\{([^}]+)\}\}/).flatten.map(&:strip).uniq
  end
end
