class MarcosxAi::ReplyStyle
  EMOJI = /\p{Extended_Pictographic}|\p{Regional_Indicator}|[0-9#*]\uFE0F?\u20E3/u

  def self.recent_text(history)
    history.select { |item| item[:role] == 'assistant' }.map do |item|
      text = item[:content].to_s
      begin
        parsed = JSON.parse(text)
        parsed.is_a?(Hash) ? parsed.fetch('text', text) : text
      rescue JSON::ParserError
        text
      end
    end
  end

  def self.apply(parts, assistant:, recent_messages: [])
    mode = assistant.resolved_config[:emoji_usage]
    return parts if mode == 'expressive'

    recent = recent_messages.last(3).join(' ').scan(/\X/).select { |character| character.match?(EMOJI) }
    used = false
    parts.map do |part|
      part.scan(/\X/).map do |character|
        next character unless character.match?(EMOJI)

        allowed = mode == 'occasional' && !used && !recent.include?(character) && recent.empty?
        used = true if allowed
        allowed ? character : ''
      end.join.gsub(/[ \t]{2,}/, ' ').strip
    end.compact_blank
  end
end
