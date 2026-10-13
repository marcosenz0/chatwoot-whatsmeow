require 'rails_helper'

RSpec.describe 'MarcoXIA files API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/marcosx_ai/assistants/#{assistant.id}/resources" }

  it 'uploads a native image, edits its context, excludes disabled items and deletes without changing agent activation' do
    image = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.png'), 'image/png')
    post endpoint, params: { resource: { title: 'Photo', description: 'Send this reference photo when requested', kind: 'file', file: image } },
                   headers: admin.create_new_auth_token
    expect(response).to have_http_status(:created), response.body
    item = response.parsed_body['resource']
    expect(item).to include('kind' => 'image', 'enabled' => true)
    expect(item['file_url']).to be_present
    expect(item['thumb_url']).to be_present
    patch "#{endpoint}/#{item['id']}", params: { resource: { enabled: false, description: 'Updated context' } },
                                      headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(assistant.resources.available).to be_empty
    expect(assistant.reload.auto_response_enabled?).to be(false)
    get endpoint, params: { search: 'Updated' }, headers: admin.create_new_auth_token
    expect(response.parsed_body['total']).to eq(1)
    delete "#{endpoint}/#{item['id']}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:no_content)
    expect(assistant.resources).to be_empty
  end

  it 'validates links and rejects non-admins, foreign agents and attachment IDs instead of uploads' do
    payload = { resource: { title: 'Link', description: 'A useful reference', kind: 'link', url: 'javascript:alert(1)' } }
    post endpoint, params: payload, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    payload[:resource][:url] = 'https://example.com/info'
    post endpoint, params: payload, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    post endpoint, params: payload, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('resource', 'id')
    other = account.marcosx_ai_assistants.create!(name: 'Other')
    patch endpoint.sub(assistant.id.to_s + '/resources', other.id.to_s + '/resources') + "/#{id}",
          params: { resource: { enabled: false } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    payload[:resource] = { title: 'File', description: 'A file', kind: 'file', file: 'some-signed-blob' }
    post endpoint, params: payload, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'uploads a video for the browser preview while native video previewers remain disabled' do
    video = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.mp4'), 'video/mp4')
    post endpoint, params: { resource: { title: 'Video', description: 'A reference video', kind: 'file', file: video } },
                   headers: admin.create_new_auth_token
    expect(response).to have_http_status(:created), response.body
    expect(response.parsed_body['resource']).to include('kind' => 'video', 'enabled' => true)
    expect(response.parsed_body.dig('resource', 'file_url')).to be_present
  end

  it 'saves a multipart batch with separate descriptions and availability in the selected agent catalog' do
    post "#{endpoint}/create_batch", params: { resources: [
      { title: 'Photo', description: 'A profile photo', kind: 'file', enabled: 'true',
        file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.png'), 'image/png') },
      { title: 'Video', description: 'A presentation video', kind: 'file', enabled: 'false',
        file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.mp4'), 'video/mp4') }
    ] }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:created), response.body
    expect(response.parsed_body['resources']).to contain_exactly(
      include('title' => 'Photo', 'description' => 'A profile photo', 'kind' => 'image', 'enabled' => true),
      include('title' => 'Video', 'description' => 'A presentation video', 'kind' => 'video', 'enabled' => false)
    )
    expect(assistant.resources.available.pluck(:title)).to eq(['Photo'])
    expect(assistant.reload.auto_response_enabled?).to be(false)
    expect(assistant.resources.map(&:file).map(&:attached?)).to all(be(true))
  end

  it 'rolls back all records and blobs when any batch description is invalid' do
    blob_count = ActiveStorage::Blob.count
    post "#{endpoint}/create_batch", params: { resources: [
      { title: 'Valid', description: 'A photo', kind: 'file',
        file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.png'), 'image/png') },
      { title: 'Invalid', description: '', kind: 'file',
        file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.mp4'), 'video/mp4') }
    ] }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.resources.count).to eq(0)
    expect(ActiveStorage::Blob.count).to eq(blob_count)
  end

  it 'enforces remaining catalog capacity for the entire batch without partial creation' do
    stub_const('MarcosxAi::Resource::MAX_ITEMS', 2)
    assistant.resources.create!(account: account, title: 'Saved', description: 'A link', kind: 'link', url: 'https://example.com')
    post "#{endpoint}/create_batch", params: { resources: [
      { title: 'One', description: 'First photo', kind: 'file',
        file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.png'), 'image/png') },
      { title: 'Two', description: 'Second photo', kind: 'file',
        file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.png'), 'image/png') }
    ] }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.resources.pluck(:title)).to eq(['Saved'])
  end

  it 'rejects malformed batch shapes, non-upload sources, non-admins and foreign-account agents' do
    payload = { resources: [{ title: 'File', description: 'A file', kind: 'file', file: 'signed-blob' }] }
    post "#{endpoint}/create_batch", params: payload, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{endpoint}/create_batch", params: payload, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{endpoint}/create_batch", params: { resources: { file: 'wrong shape' } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    foreign = create(:account).marcosx_ai_assistants.create!(name: 'Foreign')
    post endpoint.sub("/#{assistant.id}/resources", "/#{foreign.id}/resources") + '/create_batch',
         params: payload, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(assistant.resources.count).to eq(0)
    expect(foreign.resources.count).to eq(0)
  end
end
