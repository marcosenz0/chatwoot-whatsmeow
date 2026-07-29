require 'rails_helper'

RSpec.describe Whatsapp::CloudWebhookPayloadSplitter do
  it 'isolates call events and call statuses so Enterprise does not process calls twice' do
    params = {
      object: 'whatsapp_business_account',
      entry: [{
        changes: [{
          field: 'calls',
          value: {
            metadata: { phone_number_id: '123', display_phone_number: '5563999999999' },
            contacts: [{ wa_id: '111' }, { wa_id: '222' }],
            calls: [
              { id: 'call-1', from: '111', event: 'connect' },
              { id: 'call-2', from: '222', event: 'terminate' }
            ],
            statuses: [
              { id: 'call-1', type: 'call', status: 'RINGING' },
              { id: 'call-2', type: 'call', status: 'ACCEPTED' }
            ]
          }
        }]
      }]
    }

    payloads = described_class.new(params: params).perform
    values = payloads.map { |payload| payload.dig(:entry, 0, :changes, 0, :value) }

    expect(values.filter_map { |value| value[:calls]&.first&.dig(:id) }).to contain_exactly('call-1', 'call-2')
    expect(values.filter_map { |value| value[:statuses]&.first&.dig(:id) }).to contain_exactly('call-1', 'call-2')
    expect(values).to all(satisfy { |value| value[:calls].blank? || value[:statuses].blank? })
    expect(payloads.length).to eq(4)
  end
end
