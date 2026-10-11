require 'rails_helper'

RSpec.describe MarcosxAi::VoiceClient do
  let(:account) { create(:account) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }
  let(:client) { described_class.new(assistant: assistant) }
  let(:key) { 'voice-key-for-test' }

  before do
    assistant.update!(config: assistant.resolved_config.deep_merge(voice: { minimax: { voice_id: 'test_voice' } }))
  end

  it 'does not call a voice provider without a configured key' do
    expect { client.synthesize('Olá, tudo bem?') }.to raise_error(described_class::Error)
    expect(a_request(:post, 'https://api.minimax.io/v1/t2a_v2')).not_to have_been_made
    expect(assistant.voice_ready?).to be(false)
  end

  it 'stores keys encrypted and exposes only configuration status' do
    skip 'CI provides encryption keys' unless Chatwoot.encryption_configured?
    credential = assistant.voice_credentials.create!(account: account, provider: 'minimax', api_key: key)
    ciphertext = MarcosxAi::VoiceCredential.connection.select_value(
      "SELECT api_key FROM marcosx_ai_voice_credentials WHERE id = #{credential.id}"
    )
    expect(ciphertext).not_to include(key)
    expect(credential.reload.api_key).to eq(key)
    expect(credential.redacted).to eq(provider: 'minimax', configured: true)
    expect(assistant.voice_ready?).to be(false)
  end

  it 'rejects an encryptionless server and keys belonging to a different account' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    credential = assistant.voice_credentials.new(account: create(:account), provider: 'minimax', api_key: key)
    expect(credential).not_to be_valid
    expect(credential.errors[:assistant]).to be_present
    expect(credential.errors[:api_key]).to be_present
  end

  it 'sends a bounded Portuguese speech request to MiniMax and decodes hexadecimal audio' do
    skip 'CI provides encryption keys' unless Chatwoot.encryption_configured?
    assistant.voice_credentials.create!(account: account, provider: 'minimax', api_key: key)
    request = stub_request(:post, 'https://api.minimax.io/v1/t2a_v2')
              .with(headers: { 'Authorization' => "Bearer #{key}" }) { |req|
      data = JSON.parse(req.body)
      data['voice_setting']['voice_id'] == 'test_voice' && data['text'] == 'Olá, tudo bem?' &&
        data['language_boost'] == 'Portuguese' && data['stream'] == false
    }.to_return(status: 200, body: { data: { audio: '494433' }, base_resp: { status_code: 0 } }.to_json)
    expect(client.synthesize('Olá, tudo bem?')).to eq('ID3')
    expect(request).to have_been_requested.once
  end

  it 'uses the chosen ElevenLabs voice and never includes a key in provider errors' do
    skip 'CI provides encryption keys' unless Chatwoot.encryption_configured?
    assistant.update!(config: assistant.resolved_config.deep_merge(voice: { provider: 'elevenlabs', elevenlabs: { voice_id: 'owned_voice' } }))
    assistant.voice_credentials.create!(account: account, provider: 'elevenlabs', api_key: key)
    request = stub_request(:post, 'https://api.elevenlabs.io/v1/text-to-speech/owned_voice?output_format=mp3_44100_128')
              .with(headers: { 'xi-api-key' => key }).to_return(status: 401, body: "secret: #{key}")
    expect { client.synthesize('Olá') }.to raise_error(described_class::Error) { |error| expect(error.message).not_to include(key) }
    expect(request).to have_been_requested.once
  end

  it 'keeps URLs out of audio and normalizes numeric speech before synthesis' do
    skip 'CI provides encryption keys' unless Chatwoot.encryption_configured?
    assistant.voice_credentials.create!(account: account, provider: 'minimax', api_key: key)
    expect { client.synthesize('Abra https://example.com') }.to raise_error(described_class::Error)
    text_client = instance_double(MarcosxAi::ProviderClient)
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(text_client)
    expect(text_client).to receive(:chat).and_return({ text: 'São vinte e três itens.' }.to_json)
    request = stub_request(:post, 'https://api.minimax.io/v1/t2a_v2').with { |req|
      JSON.parse(req.body)['text'] == 'São vinte e três itens.'
    }.to_return(status: 200, body: { data: { audio: '494433' }, base_resp: { status_code: 0 } }.to_json)
    expect(client.synthesize('São 23 itens.')).to eq('ID3')
    expect(request).to have_been_requested.once
  end
end
