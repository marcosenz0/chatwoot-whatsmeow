export const transcriptionDefaults = { provider: 'agent', model: '' };

export const voiceDefaults = {
  enabled: false,
  provider: 'minimax',
  mode: 'requested',
  send_text: false,
  max_characters: 1500,
  min_text_turns: 6,
  long_message_characters: 450,
  instructions:
    'Use português brasileiro e frases curtas. Escreva números, datas e horários por extenso.',
  pronunciation: '',
  minimax: {
    voice_id: '',
    model: 'speech-2.8-hd',
    speed: 1,
    volume: 1,
    pitch: 0,
  },
  elevenlabs: {
    voice_id: '',
    model: 'eleven_multilingual_v2',
    speed: 1,
    stability: 0.5,
    similarity_boost: 0.75,
    style: 0,
  },
};
