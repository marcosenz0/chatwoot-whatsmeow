require 'rails_helper'

RSpec.describe Whatsmeow::SendOnWhatsmeowService do
  subject(:service) { described_class.new(message: message) }

  let(:file) do
    double(
      'Active Storage attachment',
      attached?: true,
      filename: ActiveStorage::Filename.new('audio.mp3'),
      content_type: 'audio/mpeg',
      download: 'audio-content'
    )
  end
  let(:attachment) do
    instance_double(
      Attachment,
      id: 42,
      file: file,
      file_type: 'audio',
      meta: {},
      audio?: true,
      download_url: 'https://chatwoot.example/rails/active_storage/disk/audio'
    )
  end
  let(:message) do
    instance_double(
      Message,
      attachments: [attachment],
      content_attributes: { 'whatsmeow_recorded_audio' => recorded_audio }
    )
  end
  let(:recorded_audio) { true }

  describe '#attachments_payload' do
    it 'preserves the recorded voice message flag' do
      payload = service.send(:attachments_payload).first

      expect(payload).to include(
        recorded_audio: true,
        data_base64: Base64.strict_encode64('audio-content')
      )
    end

    context 'when the audio is sent as a regular file' do
      let(:recorded_audio) { false }

      it 'does not mark the attachment as a recorded voice message' do
        expect(service.send(:attachments_payload).first[:recorded_audio]).to be(false)
      end
    end

    context 'when the worker cannot access the local Active Storage file' do
      let(:downloaded_file) { instance_double(SafeFetch::Result, tempfile: StringIO.new('recovered-audio-content')) }

      before do
        allow(file).to receive(:download).and_raise(ActiveStorage::FileNotFoundError)
        allow(SafeFetch).to receive(:fetch)
          .with(
            attachment.download_url,
            allowed_content_type_prefixes: %w[application/ audio/ image/ text/ video/]
          )
          .and_yield(downloaded_file)
      end

      it 'downloads the attachment through the web service and keeps it recorded' do
        payload = service.send(:attachments_payload).first

        expect(payload).to include(
          recorded_audio: true,
          data_base64: Base64.strict_encode64('recovered-audio-content')
        )
      end
    end
  end
end
