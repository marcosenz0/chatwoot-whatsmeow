require 'rails_helper'

RSpec.describe 'MarcoXIA Groq text and vision' do
  let(:account) { create(:account) }
  let!(:hook) do
    create(:integrations_hook, account: account, app_id: 'audio_transcription',
                               settings: { provider: 'groq', groq_api_key: 'groq-integration-secret' })
  end
  let(:assistant) do
    account.marcosx_ai_assistants.create!(name: 'Support', config: {
      provider: 'groq', model: 'openai/gpt-oss-120b',
      vision: { provider: 'groq', model: 'qwen/qwen3.8-27b', max_dimension: 800, video_frames: 6, video_interval_seconds: 2 }
    })
  end
  let(:message) { create(:message, account: account) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :image) }
  let(:client) { instance_double(MarcosxAi::ProviderClient) }
  let(:image_client) { instance_double(MarcosxAi::ProviderClient) }
  let(:service) { MarcosxAi::MediaContext.new(attachment: attachment, assistant: assistant, client: client) }

  it 'reuses the saved Groq integration without copying or disclosing its key' do
    connection = MarcosxAi::Credential.for_provider(account, 'groq')
    expect(connection.api_key).to eq('groq-integration-secret')
    expect(connection).not_to be_persisted
    expect(connection.redacted).to include(configured: true, enabled: true, source: 'integration')
    expect(connection.redacted.to_json).not_to include('groq-integration-secret')
    expect(assistant.available?).to be(true)
    expect { assistant.update!(config: assistant.config.merge('auto_response_enabled' => true)) }.not_to raise_error
  end

  it 'honors an explicitly disabled Groq connection instead of using the integration key' do
    account.marcosx_ai_credentials.create!(provider: 'groq', api_key: 'own-key', enabled: false)
    expect(assistant.available?).to be(false)
    expect { assistant.update!(config: assistant.config.merge('auto_response_enabled' => true)) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'does not borrow another account integration' do
    other = create(:account)
    expect(MarcosxAi::Credential.for_provider(other, 'groq')).to be_nil
  end

  it 'identifies Qwen vision and both models reasoning capabilities, with the provider image limit' do
    expect(MarcosxAi::ModelCatalog.describe('qwen/qwen3.8-27b', 'groq')).to include(vision: true, reasoning: true, max_images: 3, recommended: true)
    expect(MarcosxAi::ModelCatalog.describe('openai/gpt-oss-120b', 'groq')).to include(vision: false, reasoning: true)
    expect(MarcosxAi::ModelCatalog.conversational?('canopylabs/orpheus-v1-english', 'groq')).to be(false)
  end

  it 'sends actual image pixels to Qwen while keeping the GPT-OSS conversation client separate' do
    attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'image.png', content_type: 'image/png')
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(image_client)
    allow(image_client).to receive(:chat).and_return('A visual description')
    expect(client).not_to receive(:chat)
    expect(service.describe).to eq('A visual description')
    expect(MarcosxAi::ProviderClient).to have_received(:new).with(hash_including(provider: 'groq', model: 'qwen/qwen3.8-27b'))
    expect(image_client).to have_received(:chat).with(purpose: 'media_description', messages: array_including(
      hash_including(role: 'user', content: array_including(hash_including(type: 'input_image', image_url: start_with('data:image/jpeg;base64,'))))
    ))
    expect(attachment.reload.meta['marcosx_ai_description']).to eq('A visual description')
  end

  it 'limits video frames to three for Qwen even if six are configured' do
    attachment.update!(file_type: :video)
    attachment.file.attach(io: Rails.root.join('spec/assets/sample.mp4').open, filename: 'video.mp4', content_type: 'video/mp4')
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(image_client)
    allow(image_client).to receive(:chat).and_return('Sampled video')
    expect(service.describe).to eq('Sampled video')
    expect(image_client).to have_received(:chat) do |args|
      parts = args[:messages].last[:content]
      expect(parts.count { |part| part[:type] == 'input_image' }).to be_between(1, 3)
      expect(parts.pluck(:text).compact.join).to include('até 3 quadros', 'cada 2 segundos')
    end
  end

  it 'supports reasoning and JSON replies on both Groq chat models using the integration connection' do
    %w[qwen/qwen3.8-27b openai/gpt-oss-120b].each do |model|
      stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').with do |request|
        body = JSON.parse(request.body)
        body['model'] == model && body['reasoning_effort'] == 'low' && body['response_format'] == { 'type' => 'json_object' }
      end.to_return(status: 200, body: { choices: [{ message: { content: '{"messages":["Hello"]}' } }] }.to_json,
                    headers: { 'Content-Type' => 'application/json' })
      result = MarcosxAi::ProviderClient.new(account: account, provider: 'groq', model: model, reasoning_effort: 'low')
                                       .chat(messages: [{ role: 'user', content: 'Return JSON' }], schema: MarcosxAi::ReplyPlan::SCHEMA)
      expect(JSON.parse(result)['messages']).to eq(['Hello'])
    end
  end

  it 'queues coverage refresh without synchronously serializing every conversation' do
    assistant
    expect(MarcosxAi::CoverageRefreshJob).to receive(:perform_later).with(assistant.id)
    assistant.update!(description: 'Changed')
  end

  it 'rejects text-only image models and invalid image settings at the configuration boundary' do
    config = assistant.resolved_config
    config[:vision][:model] = 'openai/gpt-oss-120b'
    expect { MarcosxAi::ConfigurationValidator.validate!(config, account: account) }.to raise_error(ArgumentError)
    config[:vision][:model] = 'qwen/qwen3.8-27b'
    config[:vision][:video_frames] = 0
    expect { MarcosxAi::ConfigurationValidator.validate!(config, account: account) }.to raise_error(ArgumentError)
  end
end
