# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pipelines::DefaultSeeder do
  describe '#perform!' do
    let(:account) { create(:account) }

    it 'creates the default pipeline and default CRM stages' do
      pipeline = described_class.new(account: account).perform!

      expect(pipeline.name).to eq('Funil principal')
      expect(pipeline).to be_default
      expect(pipeline.active_stages.pluck(:name)).to eq(
        ['Novo lead', 'Contato feito', 'Qualificado', 'Proposta enviada', 'Negociação', 'Ganho', 'Perdido']
      )
    end

    it 'does not duplicate pipelines when one already exists' do
      existing_pipeline = create(:conversation_pipeline, account: account)

      expect(described_class.new(account: account).perform!).to eq(existing_pipeline)
      expect(account.conversation_pipelines.count).to eq(1)
    end

    it 'does not backfill conversations into the first stage' do
      open_conversation = create(:conversation, account: account, status: 'open')
      resolved_conversation = create(:conversation, account: account, status: 'resolved')

      described_class.new(account: account).perform!

      expect(open_conversation.reload.conversation_pipeline).to be_nil
      expect(open_conversation.conversation_pipeline_stage).to be_nil
      expect(open_conversation.pipeline_stage_entered_at).to be_nil
      expect(resolved_conversation.reload.conversation_pipeline).to be_nil
    end
  end
end
