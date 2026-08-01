require 'rails_helper'

RSpec.describe Whatsapp::ProcessCampaignDeliveryJob do
  subject(:perform_job) { job.perform(delivery.id) }

  let(:job) { described_class.new }
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
  let(:contact) { create(:contact, :with_phone_number, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: contact.phone_number.delete('+')) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox
    )
  end
  let(:campaign) do
    create(
      :campaign,
      account: account,
      inbox: inbox,
      campaign_status: :processing,
      template_params: {
        'name' => 'approved_template',
        'language' => 'pt_BR',
        'processed_params' => { 'body' => { '1' => contact.name } }
      }
    )
  end
  let(:delivery) do
    WhatsappCampaignDelivery.create!(
      account: account,
      campaign: campaign,
      contact: contact,
      phone_number: contact.phone_number,
      status: :queued
    )
  end
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      status: message_status,
      source_id: source_id,
      external_error: external_error
    )
  end
  let(:message_status) { :sent }
  let(:source_id) { nil }
  let(:external_error) { nil }

  before do
    allow(job).to receive(:build_message).with(delivery).and_return(message)
  end

  context 'when the message is still pending provider acceptance' do
    it 'associates the message and keeps the delivery and campaign processing' do
      perform_job

      expect(delivery.reload).to have_attributes(
        message_id: message.id,
        status: 'processing',
        source_id: nil,
        sent_at: nil
      )
      expect(campaign.reload).to be_processing
    end
  end

  context 'when the provider has accepted the message' do
    let(:source_id) { 'wamid.accepted-message' }

    it 'synchronizes the delivery as sent and completes the campaign' do
      perform_job

      expect(delivery.reload).to have_attributes(
        message_id: message.id,
        status: 'sent',
        source_id: source_id
      )
      expect(delivery.sent_at).to be_present
      expect(campaign.reload).to be_completed
    end
  end

  context 'when message delivery has failed' do
    let(:message_status) { :failed }
    let(:external_error) { '131047: Re-engagement message required' }

    it 'synchronizes the delivery as failed and completes the campaign' do
      perform_job

      expect(delivery.reload).to have_attributes(
        message_id: message.id,
        status: 'failed',
        error_message: external_error
      )
      expect(delivery.failed_at).to be_present
      expect(campaign.reload).to be_completed
    end
  end
end
