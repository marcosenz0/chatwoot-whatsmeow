require 'rails_helper'

describe Instagram::PreviewUrl do
  it 'normalizes profile links and strips tracking parameters' do
    expect(described_class.parse('https://instagram.com/example.user/?igsh=tracking'))
      .to eq(url: 'https://www.instagram.com/example.user/', kind: 'profile', username: 'example.user')
  end

  it 'normalizes author-prefixed and plural reels links' do
    expect(described_class.parse('https://www.instagram.com/example/reel/AbC123/'))
      .to eq(url: 'https://www.instagram.com/reel/AbC123/', kind: 'media')
    expect(described_class.parse('https://www.instagram.com/reels/AbC123/'))
      .to eq(url: 'https://www.instagram.com/reel/AbC123/', kind: 'media')
  end

  [nil, 'https://instagram.com.evil.example/test/', 'https://instagram.com/direct/',
   'https://user:password@instagram.com/test/', 'https://instagram.com:444/test/',
   'https://instagram.com/p/abc/embed/', 'javascript:alert(1)'].each do |value|
    it "rejects #{value.inspect}" do
      expect(described_class.parse(value)).to be_nil
    end
  end
end
