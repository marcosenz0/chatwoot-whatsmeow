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

  it 'rejects more than ten interactive options' do
    9.times do |index|
      definition['nodes'][1]['config']['buttons'] << { 'id' => "option-#{index}", 'title' => "Option #{index}" }
    end

    expect(errors).to include('message node message supports at most ten interactive options')
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

  context 'with an official media block' do
    let(:audio_blob) { get_blob_for('spec/assets/sample.ogg', 'audio/ogg') }

    before do
      definition['nodes'][1].replace(
        'id' => 'media',
        'type' => 'media',
        'config' => {
          'media_type' => 'audio',
          'blob_signed_id' => audio_blob.signed_id,
          'is_voice_message' => true
        }
      )
      definition['edges'].reject! { |edge| edge['source'] == 'message' }
      definition['edges'][0]['target'] = 'media'
      definition['edges'] << {
        'id' => 'edge-media',
        'source' => 'media',
        'target' => 'end',
        'source_handle' => 'default'
      }
    end

    it 'accepts a media-only journey with an OGG/Opus voice note' do
      expect(errors).to be_empty
    end

    it 'requires an uploaded file before publishing' do
      definition['nodes'][1]['config']['blob_signed_id'] = ''

      expect(errors).to include('media node media needs an uploaded file')
    end
  end

  context 'with a location block' do
    before do
      definition['nodes'][1].replace(
        'id' => 'location',
        'type' => 'location',
        'config' => { 'latitude' => '-10.184', 'longitude' => '-48.3336' }
      )
      definition['edges'].reject! { |edge| edge['source'] == 'message' }
      definition['edges'][0]['target'] = 'location'
      definition['edges'] << {
        'id' => 'edge-location',
        'source' => 'location',
        'target' => 'end',
        'source_handle' => 'default'
      }
    end

    it 'accepts valid coordinates' do
      expect(errors).to be_empty
    end

    it 'rejects coordinates outside the accepted range' do
      definition['nodes'][1]['config']['latitude'] = '100'

      expect(errors).to include('location node location needs a latitude between -90 and 90')
    end
  end

  context 'with a contact-card block' do
    before do
      definition['nodes'][1].replace(
        'id' => 'contact',
        'type' => 'contact',
        'config' => { 'name' => 'Marcos', 'phone' => '+5563999999999' }
      )
      definition['edges'].reject! { |edge| edge['source'] == 'message' }
      definition['edges'][0]['target'] = 'contact'
      definition['edges'] << {
        'id' => 'edge-contact',
        'source' => 'contact',
        'target' => 'end',
        'source_handle' => 'default'
      }
    end

    it 'accepts a named contact with a phone number' do
      expect(errors).to be_empty
    end

    it 'rejects a contact without a phone number' do
      definition['nodes'][1]['config']['phone'] = ''

      expect(errors).to include('contact node contact needs a phone number')
    end
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
