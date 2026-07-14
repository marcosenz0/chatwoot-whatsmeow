require 'rails_helper'

RSpec.describe Whatsmeow::SessionClient do
  describe '.service_urls' do
    it 'uses only configured service URLs when present' do
      with_modified_env WHATSMEOW_SERVICE_URL: ' http://primary:8080, http://secondary:8080, http://primary:8080 ' do
        expect(described_class.service_urls).to eq(['http://primary:8080', 'http://secondary:8080'])
      end
    end

    it 'uses default service URLs when none are configured' do
      with_modified_env WHATSMEOW_SERVICE_URL: '' do
        expect(described_class.service_urls).to eq(described_class::DEFAULT_SERVICE_URLS)
      end
    end
  end

  describe '.request' do
    let(:service_urls) { ['http://primary:8080', 'http://secondary:8080'] }
    let(:success_response) { instance_double(HTTParty::Response, body: '{"success":true}', success?: true) }

    before do
      allow(described_class).to receive(:service_urls).and_return(service_urls)
    end

    it 'fails over when connecting to the first service is refused' do
      allow(described_class).to receive(:perform_request)
        .with(:post, service_urls.first, '/statuses', { content: 'Hello' }, 30)
        .and_raise(Errno::ECONNREFUSED)
      allow(described_class).to receive(:perform_request)
        .with(:post, service_urls.second, '/statuses', { content: 'Hello' }, 30)
        .and_return(success_response)

      result = described_class.request(:post, '/statuses', body: { content: 'Hello' }, timeout: 30)

      expect(result).to eq('success' => true)
    end

    it 'does not retry after receiving an HTTP error response' do
      error_response = instance_double(HTTParty::Response, body: '{"error":"rejected"}', success?: false)
      allow(described_class).to receive(:perform_request).and_return(error_response)

      expect do
        described_class.request(:post, '/statuses', body: { content: 'Hello' })
      end.to raise_error(described_class::Error, 'rejected')
      expect(described_class).to have_received(:perform_request).once
    end

    [Net::ReadTimeout.new, Errno::ECONNRESET.new, EOFError.new('unexpected EOF')].each do |error|
      it "does not retry after #{error.class}" do
        allow(described_class).to receive(:perform_request).and_raise(error)

        expect do
          described_class.request(:delete, '/statuses/status-id')
        end.to raise_error(described_class::Error)
        expect(described_class).to have_received(:perform_request).once
      end
    end

    it 'does not retry when a response contains invalid JSON' do
      invalid_response = instance_double(HTTParty::Response, body: 'not-json', success?: true)
      allow(described_class).to receive(:perform_request).and_return(invalid_response)

      expect do
        described_class.request(:post, '/statuses', body: { content: 'Hello' })
      end.to raise_error(described_class::Error)
      expect(described_class).to have_received(:perform_request).once
    end
  end
end
