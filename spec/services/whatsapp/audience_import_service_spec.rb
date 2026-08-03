require 'rails_helper'

describe Whatsapp::AudienceImportService do
  subject(:perform_service) do
    described_class.new(
      account: account,
      inbox: inbox,
      contacts: contacts,
      consent_confirmed: consent_confirmed
    ).perform
  end

  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'whatsapp_cloud',
      validate_provider_config: false,
      sync_templates: false
    )
  end
  let(:inbox) { channel.inbox }
  let(:consent_confirmed) { true }
  let!(:opted_out_contact) do
    create(
      :contact,
      account: account,
      phone_number: '+5563999992222',
      custom_attributes: { whatsapp_opt_out: true }
    )
  end
  let(:contacts) do
    [
      { phone_number: '(63) 99999-1111', name: 'Maria', company_name: 'Acme' },
      { phone_number: '+55 63 99999-1111', name: 'Duplicado' },
      { phone_number: 'inválido', name: 'Sem telefone' },
      { phone_number: opted_out_contact.phone_number, name: 'Opt-out' }
    ]
  end

  it 'normalizes, deduplicates and imports only eligible contacts' do
    result = perform_service
    imported_contact = account.contacts.find_by(phone_number: '+5563999991111')

    expect(result).to include(total: 4, imported: 1, created: 1, duplicates: 1, invalid: 1, ignored: 1)
    expect(result[:contact_ids]).to eq([imported_contact.id])
    expect(imported_contact).to have_attributes(name: 'Maria')
    expect(imported_contact.additional_attributes['company_name']).to eq('Acme')
    expect(imported_contact.custom_attributes).to include(
      'whatsapp_opt_in' => true,
      'whatsapp_opt_in_source' => 'whatsapp_cloud_studio_import'
    )
    expect(imported_contact.contact_inboxes.exists?(inbox: inbox)).to be(true)
  end

  context 'without confirmed consent' do
    let(:consent_confirmed) { false }

    it 'rejects the import before creating contacts' do
      expect { perform_service }
        .to raise_error(described_class::Error, 'Confirme que os contatos autorizaram mensagens pelo WhatsApp')
    end
  end
end
