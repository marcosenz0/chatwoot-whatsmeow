require 'uri'

class Whatsmeow::PixPayload
  include ActiveModel::Model

  KEY_TYPES = %w[PHONE CPF EMAIL EVP].freeze
  BRAZIL_COUNTRY_CODE = '55'.freeze

  attr_reader :key_type, :key, :merchant_name

  validates :key_type, :key, :merchant_name, presence: true
  validates :key_type, inclusion: { in: KEY_TYPES }
  validates :key, length: { maximum: 255 }
  validates :merchant_name, length: { maximum: 100 }
  validate :key_matches_type

  def initialize(attributes = {})
    values = attributes.to_h.with_indifferent_access
    @key_type = values[:key_type].to_s.strip.upcase.presence
    @merchant_name = values[:merchant_name].to_s.squish.presence
    @key = normalize_key(values[:key])
  end

  def self.from_channel(channel)
    new(
      key_type: channel.pix_key_type,
      key: channel.pix_key,
      merchant_name: channel.pix_merchant_name
    )
  end

  def validate!
    return self if valid?

    raise CustomExceptions::Whatsmeow::InvalidPixPayload.new(
      code: 'invalid_pix_payload',
      message: errors.full_messages.to_sentence
    )
  end

  def to_h
    {
      key_type: key_type,
      key: key,
      merchant_name: merchant_name
    }
  end

  private

  def normalize_key(value)
    raw_key = value.to_s.strip
    return if raw_key.blank?

    case key_type
    when 'PHONE'
      normalize_phone(raw_key)
    when 'CPF'
      raw_key.delete('^0-9')
    when 'EMAIL', 'EVP'
      raw_key.downcase
    else
      raw_key
    end
  end

  def normalize_phone(value)
    digits = value.delete('^0-9')
    digits = "#{BRAZIL_COUNTRY_CODE}#{digits}" if [10, 11].include?(digits.length)
    "+#{digits}"
  end

  def key_matches_type
    return if key.blank? || key_type.blank? || KEY_TYPES.exclude?(key_type)

    errors.add(:key, :invalid) unless valid_key?
  end

  def valid_key?
    case key_type
    when 'PHONE' then key.match?(/\A\+[1-9]\d{9,14}\z/)
    when 'CPF' then valid_cpf?
    when 'EMAIL' then key.match?(URI::MailTo::EMAIL_REGEXP)
    when 'EVP' then key.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
    end
  end

  def valid_cpf?
    return false unless key.match?(/\A\d{11}\z/) && key.chars.uniq.length > 1

    digits = key.chars.map(&:to_i)
    first_digit = cpf_check_digit(digits.first(9), 10)
    second_digit = cpf_check_digit(digits.first(9) + [first_digit], 11)
    digits.last(2) == [first_digit, second_digit]
  end

  def cpf_check_digit(digits, weight)
    remainder = digits.each_with_index.sum { |digit, index| digit * (weight - index) } % 11
    remainder < 2 ? 0 : 11 - remainder
  end
end
