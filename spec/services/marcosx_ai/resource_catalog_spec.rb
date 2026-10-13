require 'rails_helper'

RSpec.describe MarcosxAi::ResourceCatalog do
  let(:account) { create(:account) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }
  let(:resource) {
    assistant.resources.create!(account: account, title: 'Information sheet', description: 'Send when the contact asks for the sheet',
                                kind: 'link', url: 'https://example.com/sheet')
  }

  it 'exposes descriptions without file URLs and rejects disabled, invented or another agent’s IDs' do
    expect(described_class.instructions(assistant)).to include(resource.title, resource.description)
    expect(described_class.validate!([resource.id], assistant)).to eq([resource.id])
    other = account.marcosx_ai_assistants.create!(name: 'Other')
    expect { described_class.validate!([resource.id], other) }.to raise_error(CustomExceptions::MarcosxAi)
    resource.update!(enabled: false)
    expect { described_class.validate!([resource.id], assistant) }.to raise_error(CustomExceptions::MarcosxAi)
    expect { described_class.validate!([0], assistant) }.to raise_error(CustomExceptions::MarcosxAi)
  end

  it 'retains a delivered file when the library item is deleted' do
    resource = assistant.resources.new(account: account, title: 'Photo', description: 'A reference photo', kind: 'file')
    resource.file.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'photo.png', content_type: 'image/png')
    resource.save!
    message = create(:message, account: account)
    attachment = message.attachments.build(account: account, file_type: 'image')
    attachment.file.attach(resource.file.blob)
    attachment.save!
    blob = resource.file.blob
    resource.destroy!
    expect(attachment.reload.file.blob).to eq(blob)
    expect(attachment.file.download).to be_present
  end
end
