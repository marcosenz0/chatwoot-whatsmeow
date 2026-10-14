import { flushPromises, mount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import ConversationVoiceDraft from '../ConversationVoiceDraft.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: {
    generateDraft: vi.fn(),
    previewConversationVoice: vi.fn(),
    sendReviewedReply: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const global = {
  stubs: {
    Dialog: {
      setup(_, { expose, emit }) {
        expose({
          open() {},
          close() {
            emit('close');
          },
        });
      },
      template: '<div><slot /></div>',
    },
    AudioPlayer: { props: ['src'], template: '<audio :src="src" />' },
  },
};
const mountDraft = () =>
  mount(ConversationVoiceDraft, { props: { conversationId: 92 }, global });

describe('Conversation voice draft', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    URL.createObjectURL = vi.fn(() => 'blob:voice-preview');
    URL.revokeObjectURL = vi.fn();
    MarcosxAiAPI.generateDraft.mockResolvedValue({
      data: {
        content: 'Oi! Como você está?',
        assistant_name: 'Selected agent',
        max_characters: 1200,
        review_token: 'text-review',
      },
    });
    MarcosxAiAPI.previewConversationVoice.mockResolvedValue({
      data: new Blob(['audio'], { type: 'audio/mpeg' }),
      headers: { 'x-marcoxia-review-token': 'voice-review' },
    });
    MarcosxAiAPI.sendReviewedReply.mockResolvedValue({
      data: { message_id: 10 },
    });
  });

  it('previews the selected conversation response and sends the exact preview only after explicit acceptance', async () => {
    const wrapper = mountDraft();
    await wrapper.vm.open();
    expect(MarcosxAiAPI.generateDraft).toHaveBeenCalledWith(
      92,
      { action: 'voice_reply' },
      { signal: expect.any(AbortSignal) }
    );
    expect(MarcosxAiAPI.previewConversationVoice).toHaveBeenCalledWith(
      92,
      'Oi! Como você está?',
      { signal: expect.any(AbortSignal) }
    );
    expect(wrapper.find('audio').attributes('src')).toBe('blob:voice-preview');
    expect(MarcosxAiAPI.sendReviewedReply).not.toHaveBeenCalled();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'MARCOX_AI.COMPOSER.VOICE_USE')
      .trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.sendReviewedReply).toHaveBeenCalledWith(
      92,
      'Oi! Como você está?',
      'voice-review',
      expect.any(Blob)
    );
    expect(wrapper.emitted('sent')).toHaveLength(1);
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:voice-preview');
    wrapper.unmount();
  });

  it('opens Reply now as an editable text review and sends only on acceptance', async () => {
    const wrapper = mountDraft();
    await wrapper.vm.open('reply_review');
    expect(MarcosxAiAPI.previewConversationVoice).not.toHaveBeenCalled();
    expect(MarcosxAiAPI.sendReviewedReply).not.toHaveBeenCalled();
    await wrapper.get('textarea').setValue('Edited text');
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'MARCOX_AI.COMPOSER.REVIEW_SEND')
      .trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.sendReviewedReply).toHaveBeenCalledWith(
      92,
      'Edited text',
      'text-review',
      null
    );
    wrapper.unmount();
  });

  it('keeps the playable preview when delivery fails so the operator can retry', async () => {
    MarcosxAiAPI.sendReviewedReply.mockRejectedValue({
      response: { data: { error: 'Delivery unavailable' } },
    });
    const wrapper = mountDraft();
    await wrapper.vm.open();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'MARCOX_AI.COMPOSER.VOICE_USE')
      .trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith('Delivery unavailable');
    expect(wrapper.find('audio').attributes('src')).toBe('blob:voice-preview');
    expect(wrapper.emitted('sent')).toBeUndefined();
    wrapper.unmount();
  });

  it('requires regeneration after editing the spoken text', async () => {
    const wrapper = mountDraft();
    await wrapper.vm.open();
    await wrapper.get('textarea').setValue('Texto corrigido');
    const accept = wrapper
      .findAll('button')
      .find(button => button.text() === 'MARCOX_AI.COMPOSER.VOICE_USE');
    expect(accept.attributes('disabled')).toBeDefined();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'MARCOX_AI.COMPOSER.VOICE_GENERATE')
      .trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.previewConversationVoice).toHaveBeenLastCalledWith(
      92,
      'Texto corrigido',
      { signal: expect.any(AbortSignal) }
    );
    expect(accept.attributes('disabled')).toBeUndefined();
    wrapper.unmount();
  });

  it('discards late generation when the operator changes conversations', async () => {
    let resolve;
    MarcosxAiAPI.generateDraft.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mountDraft();
    const pending = wrapper.vm.open();
    await wrapper.setProps({ conversationId: 93 });
    resolve({ data: { content: 'Wrong contact', max_characters: 1200 } });
    await pending;
    expect(MarcosxAiAPI.previewConversationVoice).not.toHaveBeenCalled();
    expect(wrapper.get('textarea').element.value).toBe('');
    wrapper.unmount();
  });

  it('keeps the text for correction when synthesis fails and sends nothing', async () => {
    MarcosxAiAPI.previewConversationVoice.mockRejectedValue({
      response: { data: { error: 'Insufficient voice balance' } },
    });
    const wrapper = mountDraft();
    await wrapper.vm.open();
    expect(useAlert).toHaveBeenCalledWith('Insufficient voice balance');
    expect(wrapper.get('textarea').element.value).toBe('Oi! Como você está?');
    expect(wrapper.find('audio').exists()).toBe(false);
    expect(MarcosxAiAPI.sendReviewedReply).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
