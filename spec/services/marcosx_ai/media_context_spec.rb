require 'rails_helper'

RSpec.describe MarcosxAi::MediaContext do
  let(:account) { create(:account) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }
  let(:message) { create(:message, account: account) }
  let(:client) { instance_double(MarcosxAi::ProviderClient) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }
  let(:service) { described_class.new(attachment: attachment, assistant: assistant, client: client) }

  it 'reuses an existing transcript without calling the provider' do
    attachment.update!(meta: { transcribed_text: 'The customer wants help' })
    expect(service.describe).to eq('The customer wants help')
  end

  it 'converts a WhatsApp OGG voice note to MP3 and caches the transcript' do
    attachment.file.attach(io: Rails.root.join('spec/assets/sample.ogg').open, filename: 'voice.ogg', content_type: 'audio/ogg')
    allow(client).to receive(:transcribe) do |audio|
      expect(audio.path).to end_with('.mp3')
      expect(File.size(audio.path)).to be_positive
      'A real voice note'
    end
    expect(service.describe).to eq('A real voice note')
    expect(attachment.reload.meta['transcribed_text']).to eq('A real voice note')
  end

  it 'uses actual image pixels for analysis and caches the description' do
    attachment.update!(file_type: :image)
    attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'image.png', content_type: 'image/png')
    allow(client).to receive(:chat).and_return('Image description')
    expect(service.describe).to eq('Image description')
    expect(client).to have_received(:chat).with(messages: array_including(
      hash_including(role: 'user', content: array_including(hash_including(type: 'input_image', image_url: start_with('data:image/jpeg;base64,'))))
    ))
    expect(attachment.reload.meta['marcosx_ai_description']).to eq('Image description')
  end

  it 'sends a PDF as a native file instead of pretending to read its name' do
    attachment.update!(file_type: :file)
    attachment.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: 'document.pdf', content_type: 'application/pdf')
    allow(client).to receive(:chat).and_return('PDF details')
    expect(service.describe).to eq('PDF details')
    expect(client).to have_received(:chat).with(messages: array_including(
      hash_including(role: 'user', content: array_including(hash_including(type: 'input_file', filename: 'document.pdf')))
    ))
  end

  it 'analyzes a locally stored Instagram story image using its media type' do
    attachment.update!(file_type: :ig_story)
    attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'story.png', content_type: 'image/png')
    allow(client).to receive(:chat).and_return('Story image description')
    expect(service.describe).to eq('Story image description')
    expect(client).to have_received(:chat).with(messages: array_including(
      hash_including(role: 'user', content: array_including(hash_including(type: 'input_image')))
    ))
  end

  it 'marks inaccessible external media as unavailable' do
    attachment.update!(file_type: :image, external_url: 'https://example.com/expired')
    expect(service.describe).to include('unavailable')
  end

  it 'respects the agent media setting' do
    assistant.update!(config: { process_audio: false })
    expect(service.describe).to include('not analyzed')
  end

  it 'does not try to send an image to a text-only Groq model' do
    assistant.update!(config: { provider: 'groq', model: 'llama-3.3-70b-versatile' })
    attachment.update!(file_type: :image)
    expect(service.describe).to include('not analyzed')
  end

  it 'extracts video frames through ffmpeg' do
    attachment.update!(file_type: :video)
    attachment.file.attach(io: Rails.root.join('spec/assets/sample.mp4').open, filename: 'video.mp4', content_type: 'video/mp4')
    allow(client).to receive(:chat).and_return('Video sample description')
    expect(service.describe).to eq('Video sample description')
    expect(client).to have_received(:chat).with(messages: array_including(
      hash_including(role: 'user', content: array_including(hash_including(type: 'input_image')))
    ))
  end
end

