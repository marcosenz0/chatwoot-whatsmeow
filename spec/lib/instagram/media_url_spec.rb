require 'rails_helper'

describe Instagram::MediaUrl do
  describe '.permalink' do
    %w[p reel tv].each do |type|
      it "normalizes #{type} URLs without tracking parameters" do
        expect(described_class.permalink("https://instagram.com/#{type}/AbC_123-/?igsh=test"))
          .to eq("https://www.instagram.com/#{type}/AbC_123-/")
      end
    end

    [nil, '', 'https://example.com/reel/123/', 'https://instagram.com.evil.example/reel/123/',
     'https://instagram.com/user/', 'https://lookaside.fbsbx.com/ig_messaging_cdn/file', 'invalid url'].each do |url|
      it "does not treat #{url.inspect} as an Instagram post" do
        expect(described_class.permalink(url)).to be_nil
      end
    end
  end
end
