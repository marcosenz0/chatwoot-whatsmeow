require 'rails_helper'

describe Instagram::PreviewService do
  let(:url) { 'https://www.instagram.com/p/AbC123/' }
  let(:service) { described_class.new(url: url) }

  before do
    Rails.cache.clear
  end

  it 'recovers a public cover when the embed rejects the same post' do
    stub_request(:get, url).to_return(headers: { 'Content-Type' => 'text/html' }, body: <<~HTML)
      <meta property="og:title" content="Example on Instagram">
      <meta property="og:image" content="https://scontent.cdninstagram.com/cover.jpg">
    HTML
    stub_request(:get, "#{url}embed/").to_return(status: 404)

    result = service.perform
    expect(result).to include(status: 'available', image_url: 'https://scontent.cdninstagram.com/cover.jpg')
    expect(result[:video_url]).to be_nil
  end

  it 'provides a directly playable source when public metadata supplies it' do
    stub_request(:get, url).to_return(headers: { 'Content-Type' => 'text/html' }, body: <<~HTML)
      <meta property="og:title" content="Example on Instagram">
      <meta property="og:video:secure_url" content="https://video.cdninstagram.com/reel.mp4">
    HTML
    stub_request(:get, "#{url}embed/").to_return(headers: { 'Content-Type' => 'text/html' }, body: '<html></html>')

    expect(service.perform[:video_url]).to eq('https://video.cdninstagram.com/reel.mp4')
  end

  it 'does not describe a blocked public preview as a deleted publication' do
    stub_request(:get, url).to_return(status: 403)
    stub_request(:get, "#{url}embed/").to_return(status: 400)

    expect(service.perform).to include(url: url, kind: 'media', status: 'limited', posts: [])
  end

  it 'rejects media sources outside the provider CDN' do
    stub_request(:get, url).to_return(headers: { 'Content-Type' => 'text/html' }, body: <<~HTML)
      <meta property="og:title" content="Example">
      <meta property="og:video" content="https://cdninstagram.com.evil.example/video.mp4">
    HTML
    stub_request(:get, "#{url}embed/").to_return(status: 404)

    expect(service.perform[:video_url]).to be_nil
  end

  context 'with a profile link' do
    let(:url) { 'https://www.instagram.com/example.user/' }

    it 'uses actual public profile details and up to six distinct photo previews' do
      stub_request(:get, url).to_return(status: 403)
      stub_request(:get, "#{url}embed/").to_return(headers: { 'Content-Type' => 'text/html' }, body: <<~HTML)
        <span class="FullName">Example User</span><span class="Biography">Example bio</span>
        <div class="Avatar"><img src="https://scontent.cdninstagram.com/avatar.jpg"></div>
        <a href="https://www.instagram.com/p/AbC123/"><img src="https://scontent.cdninstagram.com/post.jpg"></a>
      HTML

      expect(service.perform).to include(
        username: 'example.user', title: 'Example User', bio: 'Example bio',
        avatar_url: 'https://scontent.cdninstagram.com/avatar.jpg',
        posts: [{ url: 'https://www.instagram.com/p/AbC123/', image_url: 'https://scontent.cdninstagram.com/post.jpg' }]
      )
    end
  end
end
