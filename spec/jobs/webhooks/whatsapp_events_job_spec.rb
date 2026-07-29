require 'rails_helper'

RSpec.describe Webhooks::WhatsappEventsJob do
  subject(:job) { described_class }

  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:params)  do
    {
      object: 'whatsapp_business_account',
      phone_number: channel.phone_number,
      entry: [{
        changes: [
          {
            value: {
              metadata: {
                phone_number_id: channel.provider_config['phone_number_id'],
                display_phone_number: channel.phone_number.delete('+')
              }
            }
          }
        ]
      }]
    }
  end
  let(:process_service) { double }

  before do
    allow(process_service).to receive(:perform)
  end

  it 'enqueues the job' do
    expect { job.perform_later(params) }.to have_enqueued_job(described_class)
      .with(params)
      .on_queue('low')
  end

  context 'when whatsapp_cloud provider' do
    it 'enqueue Whatsapp::IncomingMessageWhatsappCloudService' do
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)
      job.perform_now(params)
    end

    it 'processes every entry, change, message, and status in a batched Cloud API webhook' do
      batched_params = batched_cloud_params(channel)
      processed_payloads = []
      job_instance = described_class.new

      allow(job_instance).to receive(:with_lock).and_yield
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new) do |**arguments|
        processed_payloads << arguments[:params]
        process_service
      end

      job_instance.perform(batched_params)

      message_payloads = processed_payloads.filter_map do |payload|
        value = payload.dig(:entry, 0, :changes, 0, :value)
        [value[:messages].first[:id], value[:contacts].first[:wa_id]] if value[:messages].present?
      end
      status_ids = processed_payloads.filter_map do |payload|
        payload.dig(:entry, 0, :changes, 0, :value, :statuses, 0, :id)
      end

      expect(message_payloads).to contain_exactly(
        ['wamid.first', '111'],
        ['wamid.second', '222'],
        ['wamid.third', '333']
      )
      expect(status_ids).to contain_exactly('wamid.first', 'wamid.second')
      expect(processed_payloads.length).to eq(5)
    end

    it 'processes valid Cloud entries when another entry has an unknown channel' do
      metadata = {
        phone_number_id: channel.provider_config['phone_number_id'],
        display_phone_number: channel.phone_number.delete('+')
      }
      batched_params = {
        object: 'whatsapp_business_account',
        phone_number: channel.phone_number,
        entry: [
          {
            changes: [{
              field: 'messages',
              value: {
                metadata: { phone_number_id: 'unknown-id', display_phone_number: '15550000000' },
                messages: [{ from: '999', id: 'wamid.unknown', type: 'text', text: { body: 'Unknown' } }]
              }
            }]
          },
          {
            changes: [{
              field: 'messages',
              value: {
                metadata: metadata,
                contacts: [{ wa_id: '111', profile: { name: 'Known' } }],
                messages: [{ from: '111', id: 'wamid.known', type: 'text', text: { body: 'Known' } }]
              }
            }]
          }
        ]
      }.with_indifferent_access
      processed_payloads = []
      job_instance = described_class.new

      allow(job_instance).to receive(:with_lock).and_yield
      allow(Rails.logger).to receive(:warn)
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new) do |**arguments|
        processed_payloads << arguments[:params]
        process_service
      end

      job_instance.perform(batched_params)

      expect(processed_payloads.length).to eq(1)
      expect(processed_payloads.first.dig(:entry, 0, :changes, 0, :value, :messages, 0, :id)).to eq('wamid.known')
      expect(Rails.logger).to have_received(:warn).with("Inactive WhatsApp channel: unknown - #{channel.phone_number}")
    end

    it 'continues processing the batch before retrying a media download failure' do
      batched_params = batched_cloud_params(channel)
      first_message = batched_params.dig(:entry, 0, :changes, 0, :value, :messages, 0)
      first_message[:type] = 'image'
      first_message[:image] = { id: 'media.first' }
      processed_message_ids = []
      job_instance = described_class.new

      allow(job_instance).to receive(:with_lock).and_yield
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new) do |**arguments|
        message_id = arguments[:params].dig(:entry, 0, :changes, 0, :value, :messages, 0, :id)
        service = double
        allow(service).to receive(:perform) do
          raise Whatsapp::IncomingMessageWhatsappCloudService::MediaDownloadError, 'temporary media failure' if message_id == 'wamid.first'

          processed_message_ids << message_id if message_id.present?
        end
        service
      end

      expect { job_instance.perform(batched_params) }
        .to raise_error(Whatsapp::IncomingMessageWhatsappCloudService::MediaDownloadError, 'temporary media failure')

      expect(processed_message_ids).to contain_exactly('wamid.second', 'wamid.third')
    end

    it 'retries a Cloud media payload even after the channel requests reauthorization' do
      media_params = params.deep_dup
      media_params[:entry].first[:changes].first[:value].merge!(
        contacts: [{ wa_id: '111', profile: { name: 'Media contact' } }],
        messages: [{ from: '111', id: 'wamid.media', type: 'image', image: { id: 'media-id' } }]
      )
      channel.prompt_reauthorization!

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)

      expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).with(inbox: channel.inbox, params: media_params)
      job.perform_now(media_params)
    end

    it 'will not enqueue message jobs based on phone number in the URL if the entry payload is not present' do
      params = {
        object: 'whatsapp_business_account',
        phone_number: channel.phone_number,
        entry: [{ changes: [{}] }]
      }
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)
      allow(Whatsapp::IncomingMessageService).to receive(:new)

      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      expect(Whatsapp::IncomingMessageService).not_to receive(:new)
      job.perform_now(params)
    end

    it 'will not enqueue Whatsapp::IncomingMessageWhatsappCloudService if channel reauthorization required' do
      channel.prompt_reauthorization!
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      job.perform_now(params)
    end

    it 'will not enqueue if channel is not present' do
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)

      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      expect(Whatsapp::IncomingMessageService).not_to receive(:new)
      job.perform_now(phone_number: 'random_phone_number')
    end

    it 'will not enqueue Whatsapp::IncomingMessageWhatsappCloudService if account is suspended' do
      account = channel.account
      account.update!(status: :suspended)
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)

      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new)
      expect(Whatsapp::IncomingMessageService).not_to receive(:new)
      job.perform_now(params)
    end

    it 'logs a warning when channel is inactive' do
      channel.prompt_reauthorization!
      allow(Rails.logger).to receive(:warn)

      expect(Rails.logger).to receive(:warn).with("Inactive WhatsApp channel: #{channel.phone_number}")
      job.perform_now(params)
    end

    it 'logs a warning with unknown phone number when channel does not exist' do
      unknown_phone = '+1234567890'
      allow(Rails.logger).to receive(:warn)

      expect(Rails.logger).to receive(:warn).with("Inactive WhatsApp channel: unknown - #{unknown_phone}")
      job.perform_now(phone_number: unknown_phone)
    end

    it 'uses from_user_id as the mutex sender for BSUID-only inbound messages' do
      bsuid = 'IN.2081978709342942'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:value][:messages] = [
        { from: '', from_user_id: bsuid, id: 'wamid-test', text: { body: 'Hello' }, type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'prefers from_user_id as the mutex sender for mixed phone and BSUID inbound messages' do
      bsuid = 'IN.2081978709342942'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:value][:messages] = [
        { from: '919745786257', from_user_id: bsuid, id: 'wamid-test', text: { body: 'Hello' }, type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'uses contact user_id as the mutex sender when message from_user_id is missing' do
      bsuid = 'IN.2081978709342942'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:value][:contacts] = [
        { profile: { name: 'Muhsin' }, wa_id: '919745786257', user_id: bsuid }
      ]
      wb_params[:entry].first[:changes].first[:value][:messages] = [
        { from: '919745786257', id: 'wamid-test', text: { body: 'Hello' }, type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'prefers parent BSUID as the mutex sender for inbound messages with both identifiers' do
      bsuid = 'IN.2081978709342942'
      parent_bsuid = 'IN.ENT.9081726354'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:value][:contacts] = [
        { profile: { name: 'Muhsin' }, user_id: bsuid, parent_user_id: parent_bsuid }
      ]
      wb_params[:entry].first[:changes].first[:value][:messages] = [
        { from_user_id: bsuid, from_parent_user_id: parent_bsuid, id: 'wamid-test', text: { body: 'Hello' }, type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: parent_bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'uses to_user_id as the mutex sender for BSUID-only echo messages' do
      bsuid = 'IN.2081978709342942'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:field] = 'smb_message_echoes'
      wb_params[:entry].first[:changes].first[:value][:message_echoes] = [
        { from: channel.phone_number.delete('+'), to: '', to_user_id: bsuid, id: 'wamid-test', text: { body: 'Hello' }, type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'prefers parent BSUID as the mutex sender for echo messages with both identifiers' do
      bsuid = 'IN.2081978709342942'
      parent_bsuid = 'IN.ENT.9081726354'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:field] = 'smb_message_echoes'
      wb_params[:entry].first[:changes].first[:value][:message_echoes] = [
        {
          from: channel.phone_number.delete('+'), to: '919745786257', to_user_id: bsuid, to_parent_user_id: parent_bsuid,
          id: 'wamid-test', text: { body: 'Hello' }, type: 'text'
        }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: parent_bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end

    it 'prefers to_user_id as the mutex sender for mixed phone and BSUID echo messages' do
      bsuid = 'IN.2081978709342942'
      wb_params = params.deep_dup
      wb_params[:entry].first[:changes].first[:field] = 'smb_message_echoes'
      wb_params[:entry].first[:changes].first[:value][:message_echoes] = [
        { from: channel.phone_number.delete('+'), to: '919745786257', to_user_id: bsuid, id: 'wamid-test', text: { body: 'Hello' },
          type: 'text' }
      ]
      job_instance = described_class.new
      mutex_key = format(Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: bsuid)

      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(job_instance).to receive(:with_lock).with(mutex_key, 30.seconds).and_yield

      job_instance.perform(wb_params)
    end
  end

  context 'when default provider' do
    it 'enqueue Whatsapp::IncomingMessageService' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      channel.update(provider: 'default')
      allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageService).to receive(:new)
      job.perform_now(params)
    end

    it 'preserves the original payload instead of expanding batches' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      channel.update(provider: 'default')
      batched_params = params.deep_dup
      batched_params[:entry].first[:changes].first[:value][:messages] = [
        { from: '111', id: 'wamid.first', type: 'text', text: { body: 'First' } },
        { from: '111', id: 'wamid.second', type: 'text', text: { body: 'Second' } }
      ]
      job_instance = described_class.new

      allow(job_instance).to receive(:with_lock).and_yield
      expect(Whatsapp::IncomingMessageService).to receive(:new)
        .once
        .with(inbox: channel.inbox, params: batched_params)
        .and_return(process_service)

      job_instance.perform(batched_params)
    end
  end

  context 'when whatsapp business params' do
    it 'enqueue Whatsapp::IncomingMessageWhatsappCloudService based on the number in payload' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [
          {
            changes: [
              {
                value: {
                  metadata: {
                    phone_number_id: other_channel.provider_config['phone_number_id'],
                    display_phone_number: other_channel.phone_number.delete('+')
                  }
                }
              }
            ]
          }
        ]
      }
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).with(inbox: other_channel.inbox, params: wb_params)
      job.perform_now(wb_params)
    end

    it 'Ignore reaction type message and stop raising error' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              contacts: [{ profile: { name: 'Test Test' }, wa_id: '1111981136571' }],
              messages: [{
                from: '1111981136571', reaction: { emoji: '👍' }, timestamp: '1664799904', type: 'reaction'
              }],
              metadata: {
                phone_number_id: other_channel.provider_config['phone_number_id'],
                display_phone_number: other_channel.phone_number.delete('+')
              }
            }
          }]
        }]
      }.with_indifferent_access
      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.not_to change(Message, :count)
    end

    it 'ignore reaction type message, would not create contact if the reaction is the first event' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              contacts: [{ profile: { name: 'Test Test' }, wa_id: '1111981136571' }],
              messages: [{
                from: '1111981136571', reaction: { emoji: '👍' }, timestamp: '1664799904', type: 'reaction'
              }],
              metadata: {
                phone_number_id: other_channel.provider_config['phone_number_id'],
                display_phone_number: other_channel.phone_number.delete('+')
              }
            }
          }]
        }]
      }.with_indifferent_access
      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.not_to change(Contact, :count)
    end

    it 'ignore request_welcome type message, would not create contact or conversation' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              messages: [{
                from: '1111981136571', timestamp: '1664799904', type: 'request_welcome'
              }],
              metadata: {
                phone_number_id: other_channel.provider_config['phone_number_id'],
                display_phone_number: other_channel.phone_number.delete('+')
              }
            }
          }]
        }]
      }.with_indifferent_access
      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.not_to change(Contact, :count)

      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other_channel.inbox, params: wb_params).perform
      end.not_to change(Conversation, :count)
    end

    it 'will not enque Whatsapp::IncomingMessageWhatsappCloudService when invalid phone number id' do
      other_channel = create(:channel_whatsapp, phone_number: '+1987654', provider: 'whatsapp_cloud', sync_templates: false,
                                                validate_provider_config: false)
      wb_params = {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [
          {
            changes: [
              {
                value: {
                  metadata: {
                    phone_number_id: 'random phone number id',
                    display_phone_number: other_channel.phone_number.delete('+')
                  }
                }
              }
            ]
          }
        ]
      }
      allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new).and_return(process_service)
      expect(Whatsapp::IncomingMessageWhatsappCloudService).not_to receive(:new).with(inbox: other_channel.inbox, params: wb_params)
      job.perform_now(wb_params)
    end
  end

  def batched_cloud_params(channel)
    metadata = {
      phone_number_id: channel.provider_config['phone_number_id'],
      display_phone_number: channel.phone_number.delete('+')
    }

    {
      object: 'whatsapp_business_account',
      phone_number: channel.phone_number,
      entry: [batched_first_entry(metadata), batched_second_entry(metadata)]
    }.with_indifferent_access
  end

  def batched_first_entry(metadata)
    {
      changes: [
        {
          field: 'messages',
          value: {
            metadata: metadata,
            contacts: [
              { wa_id: '222', profile: { name: 'Second' } },
              { wa_id: '111', profile: { name: 'First' } }
            ],
            messages: [
              { from: '111', id: 'wamid.first', type: 'text', text: { body: 'First' } },
              { from: '222', id: 'wamid.second', type: 'text', text: { body: 'Second' } }
            ]
          }
        },
        batched_status_change(metadata)
      ]
    }
  end

  def batched_status_change(metadata)
    {
      field: 'messages',
      value: {
        metadata: metadata,
        statuses: [
          { id: 'wamid.first', recipient_id: '111', status: 'delivered' },
          { id: 'wamid.second', recipient_id: '222', status: 'read' }
        ]
      }
    }
  end

  def batched_second_entry(metadata)
    {
      changes: [{
        field: 'messages',
        value: {
          metadata: metadata,
          contacts: [{ wa_id: '333', profile: { name: 'Third' } }],
          messages: [{ from: '333', id: 'wamid.third', type: 'text', text: { body: 'Third' } }]
        }
      }]
    }
  end
end
