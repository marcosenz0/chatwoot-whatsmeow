# https://docs.360dialog.com/whatsapp-api/whatsapp-api/media
# https://developers.facebook.com/docs/whatsapp/api/media/

class Whatsapp::IncomingMessageWhatsappCloudService < Whatsapp::IncomingMessageBaseService
  class MediaDownloadError < StandardError; end

  def perform
    super
  rescue MediaDownloadError
    release_message_dedup_lock
    raise
  end

  private

  def processed_params
    @processed_params ||= params[:entry].try(:first).try(:[], 'changes').try(:first).try(:[], 'value')
  end

  def download_attachment_file(attachment_payload)
    return super unless inbox.channel.provider == 'whatsapp_cloud'

    download_whatsapp_cloud_attachment_file(attachment_payload)
  end

  def download_whatsapp_cloud_attachment_file(attachment_payload)
    download_url = whatsapp_cloud_media_download_url(attachment_payload)
    return if download_url.blank?

    attachment_file = Down.download(download_url, headers: inbox.channel.api_headers)
    raise MediaDownloadError, 'WhatsApp media download returned no file' if attachment_file.blank?

    attachment_file
  rescue MediaDownloadError
    raise
  rescue StandardError => e
    raise MediaDownloadError, "WhatsApp media download failed: #{e.message}"
  end

  def whatsapp_cloud_media_download_url(attachment_payload)
    response = HTTParty.get(
      inbox.channel.media_url(attachment_payload[:id]),
      headers: inbox.channel.api_headers
    )
    # This url response will be failure if the access token has expired.
    if response.unauthorized?
      inbox.channel.authorization_error!
      return
    end

    raise MediaDownloadError, "WhatsApp media metadata request failed with HTTP #{response.code}" unless response.success?

    download_url = response.parsed_response['url']
    raise MediaDownloadError, 'WhatsApp media metadata response did not include a download URL' if download_url.blank?

    download_url
  end

  def release_message_dedup_lock
    Whatsapp::MessageDedupLock.new(messages_data.first[:id]).release!
  end
end
