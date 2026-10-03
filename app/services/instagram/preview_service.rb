class Instagram::PreviewService
  pattr_initialize [:url!]

  def perform
    target = Instagram::PreviewUrl.parse(url)
    raise ArgumentError, 'Invalid Instagram URL' unless target

    Rails.cache.fetch("instagram-preview/v1/#{target[:url]}", expires_in: 5.minutes) do
      @preview = target.merge(posts: [])
      read_page(target[:url])
      read_page("#{target[:url]}embed/")
      @preview.merge(status: @preview.values_at(:image_url, :avatar_url, :video_url).any?(&:present?) ? 'available' : 'limited')
    end
  end

  private

  def read_page(page_url)
    SafeFetch.fetch(page_url, allowed_content_types: ['text/html'], max_bytes: 2.megabytes, read_timeout: 5) do |result|
      doc = Nokogiri::HTML(result.tempfile.read)
      read_metadata(doc)
      read_embed(doc)
    end
  rescue SafeFetch::Error
    # A public preview can be blocked while the same URL still works in the authenticated Instagram app.
    nil
  end

  def read_metadata(doc)
    metadata = doc.css('meta[property^="og:"]').to_h { |node| [node['property'], node['content']] }
    return unless metadata['og:title'].present? && metadata['og:title'] != 'Instagram'

    @preview[:title] ||= metadata['og:title']
    @preview[:description] ||= metadata['og:description']
    image_key = @preview[:kind] == 'profile' ? :avatar_url : :image_url
    @preview[image_key] ||= media_url(metadata['og:image'])
    @preview[:video_url] ||= media_url(metadata['og:video:secure_url'] || metadata['og:video'])
  end

  def read_embed(doc)
    @preview[:username] ||= doc.at_css('.Username')&.text&.strip.presence
    @preview[:title] ||= doc.at_css('.FullName')&.text&.strip.presence
    @preview[:bio] ||= doc.at_css('.Biography')&.text&.strip.presence
    @preview[:avatar_url] ||= media_url(doc.at_css('.Avatar img')&.[]('src'))
    @preview[:image_url] ||= media_url(doc.at_css('.EmbeddedMediaImage')&.[]('src')) if @preview[:kind] == 'media'
    @preview[:video_url] ||= media_url(doc.at_css('video source, video[src]')&.[]('src'))
    return unless @preview[:kind] == 'profile'

    @preview[:posts] = doc.css('a[href] img').filter_map do |image|
      post = Instagram::PreviewUrl.parse(image.ancestors('a').first['href'])
      image_url = media_url(image['src'])
      { url: post[:url], image_url: image_url } if post && post[:kind] == 'media' && image_url
    end.uniq { |post| post[:url] }.first(6)
  end

  def media_url(value)
    uri = URI.parse(value.to_s)
    return unless uri.scheme == 'https' && uri.userinfo.nil?
    return unless %w[cdninstagram.com fbcdn.net fbsbx.com].any? { |domain| uri.host&.end_with?(".#{domain}") }

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end
end
