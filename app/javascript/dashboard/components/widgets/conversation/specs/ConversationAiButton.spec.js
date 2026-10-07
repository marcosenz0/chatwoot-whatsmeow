import { flushPromises, mount } from '@vue/test-utils';
import ConversationAiButton from '../ConversationAiButton.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: { getConversationState: vi.fn(), updateConversationState: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const active = {
  assistant_id: 1,
  assistant_name: 'Support',
  enabled: true,
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
  it('does not show a control when no agent is linked', async () => {
    MarcosxAiAPI.getConversationState.mockResolvedValue({
      data: { state: { assistant_id: null } },
    });
    const wrapper = mount(ConversationAiButton, { props });
    await flushPromises();
    expect(wrapper.find('button').exists()).toBe(false);
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
