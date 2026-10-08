import { flushPromises, mount } from '@vue/test-utils';
import { createMemoryHistory, createRouter } from 'vue-router';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import conversationRoutes from 'dashboard/routes/dashboard/conversation/conversation.routes';
import AgentAttendance from '../AgentAttendance.vue';
import AgentActivity from '../AgentActivity.vue';

vi.mock('dashboard/store', () => ({ default: {} }));
vi.mock('dashboard/routes/dashboard/conversation/ConversationView.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/marcosxAi', () => ({
  default: { getAssistantCoverage: vi.fn(), getLogs: vi.fn() },
}));
const props = {
  agent: {
    id: 1,
    name: 'Felipe',
    inbox_ids: [27],
    config: { auto_response_enabled: false, auto_start: true },
  },
  inboxes: [{ id: 27, name: 'WhatsApp' }],
};
const conversation = {
  id: 2170,
  contact_name: 'Owner',
  avatar_url: null,
  inbox_name: 'WhatsApp',
  processing: false,
};
let global;
beforeEach(async () => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/app/accounts/:accountId/captain/overview',
        component: { template: '<div />' },
      },
      conversationRoutes.routes.find(
        route => route.name === 'inbox_conversation'
      ),
    ],
  });
  await router.push('/app/accounts/2/captain/overview');
  global = { plugins: [router] };
});

describe('Agent attendance and activity', () => {
  it('shows individually enabled contacts with links to their conversations', async () => {
    MarcosxAiAPI.getAssistantCoverage.mockResolvedValue({
      data: {
        mode: 'individual',
        conversations: [conversation],
        total: 1,
        page: 1,
      },
    });
    const wrapper = mount(AgentAttendance, { props, global });
    await flushPromises();
    expect(wrapper.get('a').text()).toContain('Owner');
    expect(wrapper.get('a').text()).toContain('#2170');
    expect(wrapper.get('a').attributes('href')).toBe(
      '/app/accounts/2/conversations/2170'
    );
    expect(wrapper.text()).toContain('MARCOX_AI.COVERAGE.INDIVIDUAL');
    wrapper.unmount();
  });
  it('shows automatic inbox coverage without creating a large contact list', async () => {
    MarcosxAiAPI.getAssistantCoverage.mockResolvedValue({
      data: { mode: 'automatic', conversations: [conversation], total: null },
    });
    const wrapper = mount(AgentAttendance, {
      props: {
        ...props,
        agent: {
          ...props.agent,
          config: { auto_response_enabled: true, auto_start: true },
        },
      },
      global,
    });
    await flushPromises();
    expect(wrapper.text()).toContain('MARCOX_AI.COVERAGE.ALL_INBOXES');
    expect(wrapper.text()).toContain('WhatsApp');
    expect(wrapper.text()).not.toContain('Owner');
    expect(wrapper.find('a').exists()).toBe(false);
    wrapper.unmount();
  });
  it('keeps a late attendance response from replacing another agent contacts', async () => {
    let complete;
    MarcosxAiAPI.getAssistantCoverage.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    );
    const wrapper = mount(AgentAttendance, { props, global });
    MarcosxAiAPI.getAssistantCoverage.mockResolvedValue({
      data: { mode: 'individual', conversations: [], total: 0, page: 1 },
    });
    await wrapper.setProps({ agent: { ...props.agent, id: 2 } });
    await flushPromises();
    complete({
      data: {
        mode: 'individual',
        conversations: [conversation],
        total: 1,
        page: 1,
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Owner');
    expect(wrapper.text()).toContain('MARCOX_AI.COVERAGE.EMPTY');
    wrapper.unmount();
  });
  it('requests activity for the selected agent and changes the filter when switching', async () => {
    MarcosxAiAPI.getLogs.mockResolvedValue({
      data: {
        logs: [
          {
            id: 1,
            event: 'analysis_ready',
            conversation_id: 2170,
            created_at: '2026-10-08T12:00:00Z',
          },
        ],
      },
    });
    const wrapper = mount(AgentActivity, { props: { agentId: 1 }, global });
    await flushPromises();
    expect(MarcosxAiAPI.getLogs).toHaveBeenCalledWith(
      1,
      expect.objectContaining({ signal: expect.any(AbortSignal) })
    );
    expect(wrapper.get('a').text()).toBe('#2170');
    expect(wrapper.get('a').attributes('href')).toBe(
      '/app/accounts/2/conversations/2170'
    );
    MarcosxAiAPI.getLogs.mockResolvedValue({ data: { logs: [] } });
    await wrapper.setProps({ agentId: 2 });
    await flushPromises();
    expect(MarcosxAiAPI.getLogs).toHaveBeenCalledWith(2, expect.any(Object));
    expect(wrapper.find('a').exists()).toBe(false);
    wrapper.unmount();
  });
});
