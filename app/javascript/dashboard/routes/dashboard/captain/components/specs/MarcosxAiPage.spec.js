import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import MarcosxAiPage from '../../pages/MarcosxAiPage.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 2, navigationPath: 'overview' } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/marcosxAi', () => ({
  default: {
    getPreferences: vi.fn(),
    getAssistants: vi.fn(),
    getModels: vi.fn(),
    updateAssistant: vi.fn(),
    getLogs: vi.fn(),
  },
}));
const agent = {
  id: 1,
  name: 'Felipe',
  description: '',
  instructions: 'Be attentive',
  inbox_ids: [27],
  inboxes_count: 1,
  config: {
    provider: 'openai',
    model: 'model',
    reasoning_effort: 'medium',
    auto_response_enabled: true,
    auto_start: false,
  },
};
const store = createStore({
  getters: {
    getCurrentRole: () => 'administrator',
    'inboxes/getInboxes': () => [{ id: 27, name: 'WhatsApp' }],
  },
  actions: { 'inboxes/get': () => {} },
});

describe('MarcoXIA agent workspace', () => {
  beforeEach(() => {
    MarcosxAiAPI.getPreferences.mockResolvedValue({
      data: {
        credentials: [{ provider: 'openai', enabled: true, configured: true }],
        providers: { openai: {} },
        agent_defaults: {},
        default_prompt: '',
      },
    });
    MarcosxAiAPI.getAssistants.mockResolvedValue({
      data: { assistants: [JSON.parse(JSON.stringify(agent))] },
    });
    MarcosxAiAPI.getModels.mockResolvedValue({
      data: { models: [{ id: 'model', name: 'model', reasoning: true }] },
    });
    MarcosxAiAPI.updateAssistant.mockResolvedValue({
      data: {
        assistant: {
          ...agent,
          config: { ...agent.config, auto_response_enabled: false },
        },
      },
    });
  });
  it('quickly switches general support without overwriting unsaved profile instructions', async () => {
    const wrapper = mount(MarcosxAiPage, { global: { plugins: [store] } });
    await flushPromises();
    await wrapper.get('input[maxlength="120"]').setValue('My secretary');
    await wrapper.get('#ai-system-prompt').setValue('My pending instructions');
    const toggle = wrapper.get('main > aside [role="switch"]');
    await toggle.trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.updateAssistant).toHaveBeenCalledWith(1, {
      assistant: { config: { auto_response_enabled: false } },
    });
    expect(toggle.attributes('aria-checked')).toBe('false');
    expect(wrapper.get('input[maxlength="120"]').element.value).toBe(
      'My secretary'
    );
    expect(wrapper.get('#ai-system-prompt').element.value).toBe(
      'My pending instructions'
    );
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(
      MarcosxAiAPI.updateAssistant.mock.calls[1][1].assistant
    ).toMatchObject({
      name: 'My secretary',
      instructions: 'My pending instructions',
      config: { auto_response_enabled: false },
    });
    wrapper.unmount();
  });
  it('keeps the saved switch state when the update fails', async () => {
    MarcosxAiAPI.updateAssistant.mockRejectedValue(new Error('Unavailable'));
    const wrapper = mount(MarcosxAiPage, { global: { plugins: [store] } });
    await flushPromises();
    const toggle = wrapper.get('main > aside [role="switch"]');
    await toggle.trigger('click');
    await flushPromises();
    expect(toggle.attributes('aria-checked')).toBe('true');
    expect(toggle.attributes('disabled')).toBeUndefined();
    wrapper.unmount();
  });
});
