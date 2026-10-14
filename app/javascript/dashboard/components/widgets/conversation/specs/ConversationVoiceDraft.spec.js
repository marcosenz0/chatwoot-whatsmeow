import { flushPromises, mount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import ConversationVoiceDraft from '../ConversationVoiceDraft.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: { generateDraft: vi.fn(), previewConversationVoice: vi.fn() },
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
      },
    });
    MarcosxAiAPI.previewConversationVoice.mockResolvedValue({
      data: new Blob(['audio'], { type: 'audio/mpeg' }),
    });
  });

  it('previews the selected conversation response and adds a recorded file only after explicit acceptance', async () => {
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
    expect(wrapper.emitted('useAudio')).toBeUndefined();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'MARCOX_AI.COMPOSER.VOICE_USE')
      .trigger('click');
    expect(wrapper.emitted('useAudio')[0][0]).toMatchObject({
      isRecordedAudio: true,
      type: 'audio/mpeg',
      file: expect.any(File),
    });
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:voice-preview');
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

  it('keeps the text for correction when synthesis fails and emits no file', async () => {
    MarcosxAiAPI.previewConversationVoice.mockRejectedValue({
      response: { data: { error: 'Insufficient voice balance' } },
    });
    const wrapper = mountDraft();
    await wrapper.vm.open();
    expect(useAlert).toHaveBeenCalledWith('Insufficient voice balance');
    expect(wrapper.get('textarea').element.value).toBe('Oi! Como você está?');
    expect(wrapper.find('audio').exists()).toBe(false);
    expect(wrapper.emitted('useAudio')).toBeUndefined();
    wrapper.unmount();
  });
});
