require 'rails_helper'

RSpec.describe MarcosxAi::PixCatalog do
  let(:account) { create(:account) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }
  let!(:key) { assistant.pix_keys.create!(account: account, title: 'Primary', key_type: 'EMAIL', key: 'pix@example.com', merchant_name: 'Test holder', position: 1) }
  let(:plan) { { messages: ['Here is the Pix card'], reaction: nil, reaction_message_id: nil, handoff: false, handoff_reason: nil, pix_key_id: key.id } }

  it 'provides only enabled catalog IDs and context to the model, without actual keys or holder data' do
    disabled = assistant.pix_keys.create!(account: account, title: 'Disabled', key_type: 'EMAIL', key: 'disabled@example.com', merchant_name: 'Other holder')
    instructions = described_class.instructions(assistant)
    expect(instructions).to include('Primary', 'primary', 'pix_key_id', 'LinkPriv')
    expect(instructions).not_to include(key.key, key.merchant_name, disabled.title)
    expect(MarcosxAi::ReplyPlan.parse(plan.to_json, assistant: assistant)['pix_key_id']).to eq(key.id)
    expect { described_class.validate!(disabled.id, assistant) }.to raise_error(CustomExceptions::MarcosxAi)
    expect { described_class.validate!('1', assistant) }.to raise_error(CustomExceptions::MarcosxAi)
    expect { described_class.validate!([key.id], assistant) }.to raise_error(CustomExceptions::MarcosxAi)
  end

  it 'rejects foreign, inactive and unsupported-channel selections while allowing legacy responses without Pix' do
    other = account.marcosx_ai_assistants.create!(name: 'Other')
    expect { described_class.validate!(key.id, other) }.to raise_error(CustomExceptions::MarcosxAi)
    expect { MarcosxAi::ReplyPlan.parse(plan.to_json, assistant: assistant, pix_available: false) }.to raise_error(CustomExceptions::MarcosxAi)
    key.update!(position: nil)
    expect { MarcosxAi::ReplyPlan.parse(plan.to_json, assistant: assistant) }.to raise_error(CustomExceptions::MarcosxAi)
    expect(MarcosxAi::ReplyPlan.parse(plan.except(:pix_key_id).to_json, assistant: assistant)['pix_key_id']).to be_nil
  end

  it 'protects the active limit in the database even when callbacks are bypassed' do
    assistant.pix_keys.create!(account: account, title: 'Second', key_type: 'EMAIL', key: 'second@example.com', merchant_name: 'Test holder', position: 2)
    third = assistant.pix_keys.create!(account: account, title: 'Third', key_type: 'EMAIL', key: 'third@example.com', merchant_name: 'Test holder')
    expect { MarcosxAi::PixKey.transaction(requires_new: true) { third.update_columns(position: 1) } }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { MarcosxAi::PixKey.transaction(requires_new: true) { third.update_columns(position: 3) } }.to raise_error(ActiveRecord::StatementInvalid)
    expect(assistant.pix_keys.available.count).to eq(2)
  end

  it 'validates CPF and random keys through the same native Pix payload as manual cards' do
    cpf = assistant.pix_keys.new(account: account, title: 'CPF', key_type: 'CPF', key: '529.982.247-25', merchant_name: 'Test holder')
    expect(cpf).to be_valid
    expect(cpf.key).to eq('52998224725')
    random = assistant.pix_keys.new(account: account, title: 'Random', key_type: 'EVP', key: SecureRandom.uuid, merchant_name: 'Test holder')
    expect(random).to be_valid
    random.key = 'not-a-uuid'
    expect(random).not_to be_valid
  end
end
