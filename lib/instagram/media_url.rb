class Instagram::MediaUrl
  def self.permalink(value)
    uri = URI.parse(value.to_s)
    return unless %w[http https].include?(uri.scheme) && %w[instagram.com www.instagram.com].include?(uri.host)

    path = uri.path.match(%r{\A/(p|reel|tv)/([A-Za-z0-9_-]+)/?\z})
    "https://www.instagram.com/#{path[1]}/#{path[2]}/" if path
  rescue URI::InvalidURIError
    nil
  end
end
