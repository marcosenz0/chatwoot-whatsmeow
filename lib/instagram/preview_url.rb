class Instagram::PreviewUrl
  RESERVED_PATHS = %w[accounts direct explore stories reels p reel tv about developer legal challenge].freeze

  def self.parse(value)
    uri = URI.parse(value.to_s.strip)
    return unless %w[http https].include?(uri.scheme) && %w[instagram.com www.instagram.com].include?(uri.host)
    return if uri.userinfo.present? || ![80, 443].include?(uri.port)

    media_path = uri.path.match(%r{\A/(?:[A-Za-z0-9_.]+/)?(p|reel|reels|tv)/([A-Za-z0-9_-]+)/?\z})
    if media_path
      type = media_path[1] == 'reels' ? 'reel' : media_path[1]
      return { url: "https://www.instagram.com/#{type}/#{media_path[2]}/", kind: 'media' }
    end

    profile_path = uri.path.match(%r{\A/([A-Za-z0-9_.]{1,30})/?\z})
    return unless profile_path && RESERVED_PATHS.exclude?(profile_path[1].downcase)

    { url: "https://www.instagram.com/#{profile_path[1]}/", kind: 'profile', username: profile_path[1] }
  rescue URI::InvalidURIError
    nil
  end
end
