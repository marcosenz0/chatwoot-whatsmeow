require 'rails_helper'

RSpec.describe MarcosxAi::ReplyPlan do
  let(:assistant) { MarcosxAi::Assistant.new(name: 'Support') }
  let(:plan) { { messages: ['Hello', 'How can I help?', 'Details', 'More'], reaction: nil, reaction_message_id: nil, handoff: false, handoff_reason: nil } }

  it 'preserves the full response when limiting its parts' do
    assistant.config = { max_message_parts: 2 }
    result = described_class.parse(plan.to_json, assistant: assistant)
    expect(result['messages']).to eq(['Hello', "How can I help?\n\nDetails\n\nMore"])
  end

  it 'joins all parts when splitting is disabled without breaking URLs' do
    assistant.config = { split_messages: false }
    plan[:messages] = ['Use https://example.com/a?price=1.50', 'Total: 150.00']
    expect(described_class.parse(plan.to_json, assistant: assistant)['messages']).to eq(["Use https://example.com/a?price=1.50\n\nTotal: 150.00"])
  end

  it 'removes empty parts' do
    plan[:messages] = [' ', ' Hello ']
    expect(described_class.parse(plan.to_json, assistant: assistant)['messages']).to eq(['Hello'])
  end

  it 'splits a long paragraph into separate messages at complete sentence boundaries' do
    sentences = [
      'Entendi seu pedido e posso ajudar a conferir as informações que você já enviou.',
      'Vou considerar os detalhes dessa conversa para te orientar com mais clareza e sem repetir perguntas.',
      'Você prefere começar pelo orçamento ou pelos próximos passos?'
    ]
    plan[:messages] = [sentences.join(' ')]
    expect(described_class.parse(plan.to_json, assistant: assistant)['messages']).to eq(sentences)
  end

  it 'preserves links, numbers, abbreviations and complete lists when splitting' do
    parts = [
      'Fale com o Dr. Ricardo para confirmar os detalhes desse atendimento e o prazo que você precisa combinar com a equipe.',
      'O valor informado é R$ 150,00 e o telefone é +55 63 9264-5568.',
      "1. Abra https://example.com/a?price=1.50\n2. Confira o valor de 150.00\n3. Confirme os dados"
    ]
    plan[:messages] = [parts.first(2).join(' '), parts.last]
    expect(described_class.parse(plan.to_json, assistant: assistant)['messages']).to eq(parts)
  end

  it 'keeps paragraphs separate up to the configured maximum without dropping text' do
    assistant.config = { max_message_parts: 2 }
    plan[:messages] = ["Primeira ideia\n\nSegunda ideia\n\nTerceira ideia"]
    expect(described_class.parse(plan.to_json, assistant: assistant)['messages']).to eq(
      ['Primeira ideia', "Segunda ideia\n\nTerceira ideia"]
    )
  end

  it 'accepts a contextual reaction without a text message' do
    plan.merge!(messages: [], reaction: '👍', reaction_message_id: 12)
    expect(described_class.parse(plan.to_json, assistant: assistant)['reaction_message_id']).to eq(12)
  end

  it 'rejects invalid JSON' do
    expect { described_class.parse('oops', assistant: assistant) }.to raise_error(CustomExceptions::MarcosxAi)
  end

  it 'rejects a message that is not a string' do
    plan[:messages] = [{ text: 'hello' }]
    expect { described_class.parse(plan.to_json, assistant: assistant) }.to raise_error(CustomExceptions::MarcosxAi)
  end

  it 'rejects missing required fields' do
    plan.delete(:reaction)
    expect { described_class.parse(plan.to_json, assistant: assistant) }.to raise_error(CustomExceptions::MarcosxAi)
  end

  it 'rejects an unsupported reaction' do
    plan[:reaction] = 'invalid'
    expect { described_class.parse(plan.to_json, assistant: assistant) }.to raise_error(CustomExceptions::MarcosxAi)
  end
end

