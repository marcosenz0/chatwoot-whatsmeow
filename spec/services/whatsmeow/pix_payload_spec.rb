require 'rails_helper'

RSpec.describe Whatsmeow::PixPayload do
  describe '#validate!' do
    it 'normalizes a Brazilian phone key to E.164' do
      payload = described_class.new(
        key_type: 'phone',
        key: '(63) 99264-5568',
        merchant_name: '  Marcos   Digital  '
      ).validate!

      expect(payload.to_h).to eq(
        key_type: 'PHONE',
        key: '+5563992645568',
        merchant_name: 'Marcos Digital'
      )
    end

    it 'accepts a valid CPF key' do
      payload = described_class.new(key_type: 'CPF', key: '529.982.247-25', merchant_name: 'Marcos Digital')

      expect(payload.validate!.key).to eq('52998224725')
    end

    it 'rejects a malformed key with a structured error' do
      payload = described_class.new(key_type: 'EVP', key: 'not-a-uuid', merchant_name: 'Marcos Digital')

      expect { payload.validate! }
        .to raise_error(CustomExceptions::Whatsmeow::InvalidPixPayload) do |error|
          expect(error.to_hash.dig(:error, :code)).to eq('invalid_pix_payload')
        end
    end
  end
end
