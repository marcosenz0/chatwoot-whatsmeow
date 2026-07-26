require 'rails_helper'

describe Whatsapp::OneoffCampaignService do
  subject(:perform_service) { described_class.new(campaign: campaign).perform }

  let(:account) { create(:account) }
  let!(:whatsapp_channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'whatsapp_cloud',
      validate_provider_config: false,
      sync_templates: false
    )
  end
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:audience_label) { create(:label, account: account) }
  let(:trigger_rules) { { whatsapp_consent_confirmed: true } }
  let(:template_params) do
    {
      'name' => 'ticket_status_updated',
      'namespace' => 'test_namespace',
      'category' => 'MARKETING',
      'language' => 'pt_BR',
      'processed_params' => { 'body' => { '1' => '{{contact.name}}' } }
    }
  end
  let!(:campaign) do
    create(
      :campaign,
      inbox: whatsapp_inbox,
      account: account,
      audience: [{ type: 'Label', id: audience_label.id }],
      trigger_rules: trigger_rules,
      template_params: template_params
    )
  end

  before do
    account.enable_features!(:whatsapp_campaign)
  end

  context 'when campaign validation fails' do
    it 'rejects a campaign that is no longer active' do
      campaign.completed!

      expect { perform_service }.to raise_error('Campaign is no longer active')
    end

    it 'rejects a non-WhatsApp campaign' do
      sms_channel = create(:channel_sms, account: account)
      invalid_campaign = create(
        :campaign,
        inbox: create(:inbox, channel: sms_channel, account: account),
        account: account,
        trigger_rules: trigger_rules,
        template_params: template_params
      )

      expect { described_class.new(campaign: invalid_campaign).perform }
        .to raise_error("Invalid campaign #{invalid_campaign.id}")
    end

    it 'rejects non-official WhatsApp providers' do
      whatsapp_channel.update!(provider: 'default')

      expect { perform_service }.to raise_error('WhatsApp Cloud provider required')
    end

    it 'requires the WhatsApp campaigns feature' do
      account.disable_features!(:whatsapp_campaign)

      expect { perform_service }.to raise_error('WhatsApp campaigns feature not enabled')
    end

    context 'without confirmed audience consent' do
      let(:trigger_rules) { {} }

      it 'rejects the campaign' do
        expect { perform_service }.to raise_error('Campaign audience consent must be confirmed')
      end
    end

    context 'without template parameters' do
      let(:template_params) { nil }

      it 'rejects the campaign' do
        expect { perform_service }.to raise_error('Template parameters are required')
      end
    end
  end

  context 'when campaign is valid' do
    let!(:eligible_contact) { create(:contact, :with_phone_number, account: account) }
    let!(:opted_out_contact) do
      create(
        :contact,
        :with_phone_number,
        account: account,
        custom_attributes: { whatsapp_opt_out: true }
      )
    end
    let!(:contact_without_phone) { create(:contact, account: account, phone_number: nil) }

    before do
      [eligible_contact, opted_out_contact, contact_without_phone].each do |contact|
        contact.update_labels([audience_label.title])
      end
    end

    it 'creates deduplicated delivery records with a pre-send estimate' do
      expect { perform_service }
        .to change(WhatsappCampaignDelivery, :count).by(3)
        .and have_enqueued_job(Whatsapp::ProcessCampaignDeliveryJob).exactly(:once)

      expect(campaign.reload).to be_processing
      expect(campaign.whatsapp_campaign_deliveries.find_by(contact: eligible_contact)).to have_attributes(
        status: 'queued',
        template_category: 'MARKETING',
        currency: 'BRL',
        estimated_cost: BigDecimal('0.3217')
      )
    end

    it 'suppresses opted-out contacts and contacts without a phone number' do
      perform_service

      expect(campaign.whatsapp_campaign_deliveries.find_by(contact: opted_out_contact)).to have_attributes(
        status: 'skipped',
        error_message: 'Contact opted out of WhatsApp messages'
      )
      expect(campaign.whatsapp_campaign_deliveries.find_by(contact: contact_without_phone)).to have_attributes(
        status: 'skipped',
        error_message: 'Contact has no phone number'
      )
    end

    it 'does not create duplicate deliveries when invoked again' do
      perform_service

      expect { described_class.new(campaign: campaign).perform }
        .to raise_error('Campaign is no longer active')
        .and not_change(WhatsappCampaignDelivery, :count)
    end

    it 'completes after every queued delivery has been accepted for sending' do
      perform_service

      campaign.whatsapp_campaign_deliveries.queued.find_each(&:sent!)
      campaign.complete_whatsapp_campaign_if_finished!

      expect(campaign.reload).to be_completed
    end
  end

  context 'when the selected labels have no contacts' do
    it 'marks the campaign as failed without enqueueing deliveries' do
      expect { perform_service }
        .not_to have_enqueued_job(Whatsapp::ProcessCampaignDeliveryJob)

      expect(campaign.reload).to be_failed
    end
  end
end
