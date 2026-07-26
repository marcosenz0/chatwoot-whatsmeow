require 'rails_helper'

describe Whatsapp::Automation::DefinitionValidator do
  subject(:errors) { described_class.new(definition, publish: publish).validate }

  let(:publish) { true }
  let(:definition) do
    {
      'nodes' => [
        { 'id' => 'trigger', 'type' => 'trigger', 'config' => {} },
        {
          'id' => 'message',
          'type' => 'message',
          'config' => {
            'mode' => 'session',
            'text' => 'How can we help?',
            'buttons' => [
              { 'id' => 'sales', 'title' => 'Sales' },
              { 'id' => 'support', 'title' => 'Support' }
            ]
          }
        },
        { 'id' => 'end', 'type' => 'end', 'config' => {} }
      ],
      'edges' => [
        { 'id' => 'edge-1', 'source' => 'trigger', 'target' => 'message', 'source_handle' => 'default' },
        { 'id' => 'edge-2', 'source' => 'message', 'target' => 'end', 'source_handle' => 'sales' }
      ]
    }
  end

  it 'accepts a publishable flow with reply-button branches' do
    expect(errors).to be_empty
  end

  it 'rejects more than three reply buttons' do
    definition['nodes'][1]['config']['buttons'] << { 'id' => 'billing', 'title' => 'Billing' }
    definition['nodes'][1]['config']['buttons'] << { 'id' => 'other', 'title' => 'Other' }

    expect(errors).to include('message node message supports at most three reply buttons')
  end

  it 'rejects graph cycles when publishing' do
    definition['edges'] << {
      'id' => 'edge-3',
      'source' => 'end',
      'target' => 'message',
      'source_handle' => 'default'
    }

    expect(errors).to include('contains a cycle; published flows must terminate')
  end

  context 'when saving a draft' do
    let(:publish) { false }

    it 'allows an incomplete graph but still validates node configuration' do
      definition['nodes'].reject! { |node| node['type'] == 'trigger' }
      definition['edges'].reject! { |edge| edge['source'] == 'trigger' }

      expect(errors).to be_empty
    end
  end
end
