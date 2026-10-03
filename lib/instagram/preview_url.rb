class Instagram::PreviewUrl
  RESERVED_PATHS = %w[accounts direct explore stories reels p reel tv about developer legal challenge].freeze

  def self.parse(value)
    uri = URI.parse(value.to_s.strip)
    return unless valid_origin?(uri)

    media_target(uri.path) || profile_target(uri.path)
  rescue URI::InvalidURIError
    nil
  end

  def self.valid_origin?(uri)
    %w[http https].include?(uri.scheme) && %w[instagram.com www.instagram.com].include?(uri.host) &&
      uri.userinfo.blank? && [80, 443].include?(uri.port)
  end

  def self.media_target(path)
    media_path = path.match(%r{\A/(?:[A-Za-z0-9_.]+/)?(p|reel|reels|tv)/([A-Za-z0-9_-]+)/?\z})
    return unless media_path

    type = media_path[1] == 'reels' ? 'reel' : media_path[1]
    { url: "https://www.instagram.com/#{type}/#{media_path[2]}/", kind: 'media' }
  end

  def self.profile_target(path)
    profile_path = path.match(%r{\A/([A-Za-z0-9_.]{1,30})/?\z})
    return unless profile_path && RESERVED_PATHS.exclude?(profile_path[1].downcase)

    { url: "https://www.instagram.com/#{profile_path[1]}/", kind: 'profile', username: profile_path[1] }
  end

  private_class_method :valid_origin?, :media_target, :profile_target
end
