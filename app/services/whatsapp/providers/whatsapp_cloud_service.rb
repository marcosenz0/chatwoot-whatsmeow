class Whatsapp::Providers::WhatsappCloudService < Whatsapp::Providers::BaseService
  class TemplateSyncError < StandardError; end

  DEFAULT_GRAPH_API_VERSION = 'v22.0'.freeze

  def send_message(phone_number, message)
    @message = message

    if message.attachments.present?
      send_attachment_message(phone_number, message)
    elsif message.content_type == 'input_select'
      send_interactive_text_message(phone_number, message)
    else
      send_text_message(phone_number, message)
    end
  end

  def send_template(phone_number, template_info, message)
    template_body = template_body_parameters(template_info)

    request_body = {
      messaging_product: 'whatsapp',
      recipient_type: 'individual', # Only individual messages supported (not group messages)
      to: phone_number,
      type: 'template',
      template: template_body
    }

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: request_body.to_json
    )

    process_response(response, message)
  end

  def sync_templates
    templates = fetch_whatsapp_templates("#{business_account_path}/message_templates")
    whatsapp_channel.update!(
      message_templates: templates,
      message_templates_last_updated: Time.current
    )
  end

  def fetch_whatsapp_templates(url)
    response = HTTParty.get(url, headers: api_headers)
    raise TemplateSyncError, template_sync_error(response) unless response.success?

    next_url = next_url(response)
    templates = Array(response['data'])

    return templates + fetch_whatsapp_templates(next_url) if next_url.present?

    templates
  end

  def next_url(response)
    response['paging'] ? response['paging']['next'] : ''
  end

  def validate_provider_config?
    response = HTTParty.get("#{business_account_path}/message_templates", headers: api_headers)
    response.success?
  end

  def api_headers
    { 'Authorization' => "Bearer #{whatsapp_channel.provider_config['api_key']}", 'Content-Type' => 'application/json' }
  end

  def create_csat_template(template_config)
    csat_template_service.create_template(template_config)
  end

  def delete_csat_template(template_name = nil)
    template_name ||= CsatTemplateNameService.csat_template_name(whatsapp_channel.inbox.id)
    csat_template_service.delete_template(template_name)
  end

  def get_template_status(template_name)
    csat_template_service.get_template_status(template_name)
  end

  def media_url(media_id)
    "#{api_base_path}/#{graph_api_version}/#{media_id}"
  end

  def graph_api_version
    GlobalConfigService.load('WHATSAPP_API_VERSION', DEFAULT_GRAPH_API_VERSION)
  end

  def template_management_path
    "#{business_account_path}/message_templates"
  end

  private

  def csat_template_service
    @csat_template_service ||= Whatsapp::CsatTemplateService.new(whatsapp_channel)
  end

  def api_base_path
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end

  def phone_id_path
    "#{api_base_path}/#{graph_api_version}/#{whatsapp_channel.provider_config['phone_number_id']}"
  end

  def business_account_path
    "#{api_base_path}/#{graph_api_version}/#{whatsapp_channel.provider_config['business_account_id']}"
  end

  def send_text_message(phone_number, message)
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(message),
        to: phone_number,
        text: { body: message.outgoing_content },
        type: 'text'
      }.to_json
    )

    process_response(response, message)
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    normalize_opus_content_type(attachment)
    type = %w[image audio video].include?(attachment.file_type) ? attachment.file_type : 'document'
    type_content = build_attachment_content(type, attachment, message)
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        :messaging_product => 'whatsapp',
        :context => whatsapp_reply_context(message),
        'to' => phone_number,
        'type' => type,
        type.to_s => type_content
      }.to_json
    )

    process_response(response, message)
  end

  def voice_message?(type, attachment)
    voice_flag = attachment.meta&.[]('is_voice_message') || attachment.meta&.[](:is_voice_message)

    type == 'audio' &&
      voice_flag &&
      attachment.file.blob.content_type == 'audio/ogg'
  end

  def normalize_opus_content_type(attachment)
    return unless attachment.file.attached?
    return unless attachment.file.blob.content_type == 'audio/opus'

    attachment.file.blob.update!(content_type: 'audio/ogg')
  end

  def build_attachment_content(type, attachment, message)
    type_content = { 'link' => attachment.download_url }
    type_content['caption'] = message.outgoing_content unless %w[audio sticker].include?(type)
    type_content['filename'] = attachment.file.filename if type == 'document'
    type_content['voice'] = true if voice_message?(type, attachment)
    type_content
  end

  def error_message(response)
    # https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/#sample-response
    response.parsed_response&.dig('error', 'message')
  end

  def template_sync_error(response)
    error_message(response).presence || "WhatsApp template sync failed with status #{response.code}"
  end

  def template_body_parameters(template_info)
    template_body = {
      name: template_info[:name],
      language: {
        policy: 'deterministic',
        code: template_info[:lang_code]
      }
    }

    # Enhanced template parameters structure
    # Note: Legacy format support (simple parameter arrays) has been removed
    # in favor of the enhanced component-based structure that supports
    # headers, buttons, and authentication templates.
    #
    # Expected payload format from frontend:
    # {
    #   processed_params: {
    #     body: { '1': 'John', '2': '123 Main St' },
    #     header: {
    #       media_url: 'https://...',
    #       media_type: 'image',
    #       media_name: 'filename.pdf' # Optional, for document templates only
    #     },
    #     buttons: [{ type: 'url', parameter: 'otp123456' }]
    #   }
    # }
    # This gets transformed into WhatsApp API component format:
    # [
    #   { type: 'body', parameters: [...] },
    #   { type: 'header', parameters: [...] },
    #   { type: 'button', sub_type: 'url', parameters: [...] }
    # ]
    template_body[:components] = template_info[:parameters] || []

    template_body
  end

  def whatsapp_reply_context(message)
    reply_to = message.content_attributes[:in_reply_to_external_id]
    return nil if reply_to.blank?

    {
      message_id: reply_to
    }
  end

  def send_interactive_text_message(phone_number, message)
    payload = create_payload_based_on_items(message)
    payload[:action] = JSON.parse(payload[:action]) if payload[:action].is_a?(String)

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        to: phone_number,
        interactive: payload,
        type: 'interactive'
      }.to_json
    )

    process_response(response, message)
  end
end

Whatsapp::Providers::WhatsappCloudService.prepend_mod_with('Whatsapp::Providers::WhatsappCloudService')
