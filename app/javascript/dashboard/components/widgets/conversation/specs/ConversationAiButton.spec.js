import { flushPromises, mount } from '@vue/test-utils';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import ConversationAiButton from '../ConversationAiButton.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: { getConversationState: vi.fn(), updateConversationState: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../ConversationAiPanel.vue', () => ({
  default: {
    setup(_, { expose }) {
      expose({ open: vi.fn() });
    },
    template: '<div />',
  },
}));
const active = {
  assistant_id: 1,
  assistant_name: 'Support',
  enabled: true,
  available: true,
  status: 'active',
  processing: false,
  updated_at: '2026-10-07T10:00:00Z',
};
const props = { chat: { id: 1, status: 'open' } };

describe('Conversation AI control', () => {
  beforeEach(() => {
    MarcosxAiAPI.getConversationState.mockResolvedValue({
      data: { state: active },
    });
  });
  it('shows the active state next to the conversation actions', async () => {
    const wrapper = mount(ConversationAiButton, { props });
    await flushPromises();
    expect(wrapper.find('button').text()).toContain(
      'MARCOX_AI.CONVERSATION.ON'
    );
  });
  it('keeps a control visible when the inbox has no default agent', async () => {
    MarcosxAiAPI.getConversationState.mockResolvedValue({
      data: { state: { assistant_id: null } },
    });
    const wrapper = mount(ConversationAiButton, { props });
    await flushPromises();
    expect(wrapper.find('button').exists()).toBe(true);
    expect(wrapper.find('button').text()).toContain(
      'MARCOX_AI.CONVERSATION.OFF'
    );
  });
  it('enables new messages without asking for an immediate reply', async () => {
    MarcosxAiAPI.getConversationState.mockResolvedValue({
      data: { state: { ...active, status: 'paused_by_agent' } },
    });
    MarcosxAiAPI.updateConversationState.mockResolvedValue({
      data: { state: active },
    });
    const wrapper = mount(ConversationAiButton, { props });
    await flushPromises();
    await wrapper.get('button').trigger('click');
    expect(MarcosxAiAPI.updateConversationState).toHaveBeenCalledWith(1, {
      action: 'resume',
      reason: 'agent_action',
    });
  });
  it('updates its status from a conversation event', async () => {
    const wrapper = mount(ConversationAiButton, { props });
    await flushPromises();
    await wrapper.setProps({
      chat: {
        ...props.chat,
        marcosx_ai: {
          ...active,
          status: 'paused_by_human',
          updated_at: '2026-10-07T10:01:00Z',
        },
      },
    });
    expect(wrapper.find('button').text()).toContain(
      'MARCOX_AI.CONVERSATION.OFF'
    );
  });
  it('directly enables one conversation when general support is disabled', async () => {
    MarcosxAiAPI.getConversationState.mockResolvedValue({
      data: { state: { ...active, enabled: false, status: 'paused_by_agent' } },
    });
    MarcosxAiAPI.updateConversationState.mockResolvedValue({
      data: { state: active },
    });
    const wrapper = mount(ConversationAiButton, { props });
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.updateConversationState).toHaveBeenCalledWith(1, {
      action: 'resume',
      reason: 'agent_action',
    });
    expect(wrapper.get('button').text()).toContain('MARCOX_AI.CONVERSATION.ON');
    wrapper.unmount();
  });
  it('ignores a state fetch from a previously selected conversation', async () => {
    let complete;
    MarcosxAiAPI.getConversationState.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    );
    const wrapper = mount(ConversationAiButton, { props });
    MarcosxAiAPI.getConversationState.mockResolvedValue({
      data: {
        state: {
          ...active,
          assistant_name: 'Another',
          status: 'paused_by_agent',
        },
      },
    });
    await wrapper.setProps({ chat: { id: 2, status: 'open' } });
    await flushPromises();
    complete({ data: { state: active } });
    await flushPromises();
    expect(wrapper.find('button').text()).toContain(
      'MARCOX_AI.CONVERSATION.OFF'
    );
  });
});

describe('Analysis animation', () => {
  it('spins during generation while keeping the pause control available', async () => {
    MarcosxAiAPI.getConversationState.mockResolvedValue({
      data: { state: { ...active, processing: true } },
    });
    const wrapper = mount(ConversationAiButton, { props });
    await flushPromises();
    expect(wrapper.find('.animate-spin').exists()).toBe(true);
    expect(wrapper.find('button').attributes('disabled')).toBeUndefined();
  });
});
