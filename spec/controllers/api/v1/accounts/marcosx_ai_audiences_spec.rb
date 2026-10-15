require 'rails_helper'

RSpec.describe 'MarcoXIA audience management', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:contact) { create(:contact, account: account, name: 'Allowed person') }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/marcosx_ai/assistants/#{assistant.id}" }
  let(:link) { { title: 'Scoped file', description: 'Send on request', kind: 'link', url: 'https://example.com/item' } }

  it 'stores conversation display IDs safely and edits the allowed contacts from the full library' do
    post "#{endpoint}/resources", params: { resource: link.merge(audience: 'conversation', conversation_id: conversation.display_id) },
                                  headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created), response.body
    item = response.parsed_body['resource']
    expect(item).to include('audience' => 'conversation', 'conversation_id' => conversation.display_id, 'contact_ids' => [])
    expect(assistant.resources.last.conversation_id).to eq(conversation.id)
    patch "#{endpoint}/resources/#{item['id']}", params: { resource: { audience: 'contacts', contact_ids: [contact.id] } },
                                               headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['resource']).to include('conversation_id' => nil, 'contact_ids' => [contact.id],
                                                      'audience_contacts' => [{ 'id' => contact.id, 'name' => contact.name }])
    patch "#{endpoint}/resources/#{item['id']}", params: { resource: { audience: 'global', contact_ids: [] } },
                                               headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(assistant.resources.last).to have_attributes(audience: 'global', contact_ids: [], conversation_id: nil)
    expect(assistant.reload.auto_response_enabled?).to be(false)
  end

  it 'rejects foreign contacts, empty contact sets, duplicates and malformed scope without a partial update' do
    foreign = create(:contact)
    [{ audience: 'contacts', contact_ids: [foreign.id] }, { audience: 'contacts', contact_ids: [] },
     { audience: 'contacts', contact_ids: [contact.id, contact.id] }, { audience: 'global', contact_ids: [contact.id] },
     { audience: 'contacts', contact_ids: { id: contact.id } }, { audience: 'wrong' },
     { audience: 'conversation', conversation_id: 'wrong' }].each do |scope|
      post "#{endpoint}/resources", params: { resource: link.merge(scope) }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity), response.body
      expect(assistant.resources.count).to eq(0)
    end
  end

  it 'keeps a batch atomic when the second file has a forbidden audience' do
    entries = [conversation.contact_id, create(:contact).id].map do |id|
      { title: 'Photo', description: 'Reference', kind: 'file', audience: 'contacts', contact_ids: [id],
        file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.png'), 'image/png') }
    end
    post "#{endpoint}/resources/create_batch", params: { resources: entries }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.resources).to be_empty
  end

  it 'persists Pix audience without changing the two-active-keys limit' do
    attributes = { title: 'Main', key_type: 'EMAIL', key: 'pix@example.com', merchant_name: 'Test holder', enabled: true,
                   audience: 'conversation', conversation_id: conversation.display_id }
    post "#{endpoint}/pix_keys", params: { pix_key: attributes }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created), response.body
    key = response.parsed_body['pix_keys'].first
    expect(key).to include('audience' => 'conversation', 'conversation_id' => conversation.display_id)
    patch "#{endpoint}/pix_keys/#{key['id']}", params: { pix_key: { audience: 'contacts', contact_ids: [contact.id] } },
                                             headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['pix_keys'].first['contact_ids']).to eq([contact.id])
    expect(response.parsed_body['active_limit']).to eq(2)
  end

  it 'creates, edits and deletes a notice number without sending, enabling AI or touching existing profile options' do
    original = assistant.config.deep_dup
    attributes = { title: 'Owner', number: '+15555550101', inbox_id: inbox.id, enabled: true,
                   audience: 'conversation', conversation_id: conversation.display_id }
    expect do
      post "#{endpoint}/notification_targets", params: { notification_target: attributes }, headers: admin.create_new_auth_token, as: :json
    end.not_to change(Message, :count)
    expect(response).to have_http_status(:created), response.body
    item = response.parsed_body['notification_targets'].first
    expect(item).to include('audience' => 'conversation', 'conversation_id' => conversation.display_id)
    patch "#{endpoint}/notification_targets/#{item['id']}",
          params: { notification_target: { audience: 'contacts', contact_ids: [contact.id] } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['notification_targets'].first['contact_ids']).to eq([contact.id])
    delete "#{endpoint}/notification_targets/#{item['id']}", headers: admin.create_new_auth_token
    expect(response.parsed_body['notification_targets']).to eq([])
    expect(assistant.reload.config).to eq(original)
  end

  it 'shows existing global numbers and converts them on explicit edit without resurrecting them on deletion' do
    assistant.update!(config: { notifications: { whatsapp_numbers: ['+15555550101'], user_ids: [admin.id], inbox_id: inbox.id } })
    get "#{endpoint}/notification_targets", headers: admin.create_new_auth_token
    item = response.parsed_body['notification_targets'].first
    expect(item).to include('audience' => 'global', 'number' => '+15555550101')
    expect(assistant.notification_targets.count).to eq(0)
    patch "#{endpoint}/notification_targets/#{item['id']}",
          params: { notification_target: { audience: 'contacts', contact_ids: [contact.id] } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    managed = response.parsed_body['notification_targets'].first
    expect(managed['contact_ids']).to eq([contact.id])
    expect(assistant.reload.resolved_config[:notifications]).to include(user_ids: [admin.id], whatsapp_numbers: [])
    delete "#{endpoint}/notification_targets/#{managed['id']}", headers: admin.create_new_auth_token
    expect(response.parsed_body['notification_targets']).to eq([])
  end

  it 'searches contacts only in the current account and forbids non-admins and foreign agents' do
    contact
    foreign = create(:contact, name: 'Allowed foreign person')
    get "#{endpoint}/audience_contacts", params: { q: 'Allowed' }, headers: admin.create_new_auth_token
    expect(response.parsed_body['contacts']).to eq([{ 'id' => contact.id, 'name' => contact.name }])
    get "#{endpoint}/audience_contacts", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    foreign_assistant = foreign.account.marcosx_ai_assistants.create!(name: 'Foreign')
    get endpoint.sub("/assistants/#{assistant.id}", "/assistants/#{foreign_assistant.id}") + '/notification_targets', headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    foreign_inbox = create(:channel_whatsmeow, account: foreign.account).inbox
    post "#{endpoint}/notification_targets", params: { notification_target: { number: '+15555550101', inbox_id: foreign_inbox.id } },
                                           headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
