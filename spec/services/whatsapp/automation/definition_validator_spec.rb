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
        { 'id' => 'edge-2', 'source' => 'message', 'target' => 'end', 'source_handle' => 'sales' },
        { 'id' => 'edge-3', 'source' => 'message', 'target' => 'end', 'source_handle' => 'support' }
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
      'id' => 'edge-4',
      'source' => 'end',
      'target' => 'message',
      'source_handle' => 'default'
    }

    expect(errors).to include('contains a cycle; published flows must terminate')
  end

  it 'rejects an unconnected reply-button branch' do
    definition['edges'].reject! { |edge| edge['source_handle'] == 'support' }

    expect(errors).to include('node message needs a connection from support')
  end

  it 'rejects blank reply-button titles' do
    definition['nodes'][1]['config']['buttons'][0]['title'] = ''

    expect(errors).to include('message node message button titles must be present')
  end

  it 'rejects unreachable nodes' do
    definition['nodes'] << {
      'id' => 'orphan',
      'type' => 'end',
      'config' => {}
    }

    expect(errors).to include('contains unreachable nodes: orphan')
  end

  it 'requires values for every numbered template variable when publishing' do
    config = definition['nodes'][1]['config']
    config.replace(
      'mode' => 'template',
      'template_name' => 'order_update',
      'preview_text' => 'Hello {{1}}, order {{2}} is ready.',
      'buttons' => [],
      'processed_params' => { 'body' => { '1' => 'Marcos', '2' => '' } }
    )
    definition['edges'].reject! { |edge| edge['source'] == 'message' }
    definition['edges'] << {
      'id' => 'edge-template',
      'source' => 'message',
      'target' => 'end',
      'source_handle' => 'default'
    }

    expect(errors).to include('template node message needs values for variables 2')
  end

  it 'requires values for every named template variable when publishing' do
    config = definition['nodes'][1]['config']
    config.replace(
      'mode' => 'template',
      'template_name' => 'order_update',
      'preview_text' => 'Hello {{customer_name}}, order {{order_number}} is ready.',
      'buttons' => [],
      'processed_params' => { 'body' => { 'customer_name' => 'Marcos', 'order_number' => '' } }
    )
    definition['edges'].reject! { |edge| edge['source'] == 'message' }
    definition['edges'] << {
      'id' => 'edge-template',
      'source' => 'message',
      'target' => 'end',
      'source_handle' => 'default'
    }

    expect(errors).to include('template node message needs values for variables order_number')
  end

  context 'when saving a draft' do
    let(:publish) { false }

    it 'allows an incomplete graph and incomplete node content' do
      definition['nodes'].reject! { |node| node['type'] == 'trigger' }
      definition['edges'].reject! { |edge| edge['source'] == 'trigger' }
      definition['nodes'].find { |node| node['type'] == 'message' }['config']['text'] = ''

      expect(errors).to be_empty
    end
  end
end
