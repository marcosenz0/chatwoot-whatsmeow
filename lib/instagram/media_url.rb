class Instagram::MediaUrl
  def self.permalink(value)
    target = Instagram::PreviewUrl.parse(value)
    target[:url] if target && target[:kind] == 'media'
  end
end
