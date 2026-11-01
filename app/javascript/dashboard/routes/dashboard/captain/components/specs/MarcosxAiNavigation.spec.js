import { flushPromises, mount } from '@vue/test-utils';
import { createMemoryHistory, createRouter } from 'vue-router';
import { createStore } from 'vuex';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MarcosxAiPage from '../../pages/MarcosxAiPage.vue';
import AgentEditor from '../AgentEditor.vue';
import AgentAttendance from '../AgentAttendance.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/marcosxAi', () => ({
  default: {
    getPreferences: vi.fn(),
    getAssistants: vi.fn(),
    getModels: vi.fn(),
    getConnectionHealth: vi.fn(),
    setManualSessions: vi.fn(),
    updateAssistant: vi.fn(),
    getAssistantCoverage: vi.fn(),
  },
}));
const agent = {
  id: 1,
  name: 'Support',
  description: 'Open this agent from the card body',
  instructions: 'Existing instructions',
  inbox_ids: [],
  manual_sessions_count: 2,
  manual_sessions_paused_count: 0,
  config: {
    provider: 'groq',
    model: 'model',
    auto_response_enabled: false,
    manual_sessions_enabled: false,
  },
};
let router;
let global;
let wrapper;
beforeEach(async () => {
  HTMLDialogElement.prototype.showModal = vi.fn();
  HTMLDialogElement.prototype.close = vi.fn();
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/app/accounts/:accountId/conversations/:conversation_id',
        name: 'inbox_conversation',
        component: { template: '<div />' },
      },
      {
        path: '/app/accounts/:accountId/captain/:navigationPath',
        component: MarcosxAiPage,
      },
    ],
  });
  await router.push('/app/accounts/1/captain/overview');
  MarcosxAiAPI.getPreferences.mockResolvedValue({
    data: { credentials: [], providers: {} },
  });
  MarcosxAiAPI.getAssistants.mockResolvedValue({
    data: { assistants: [structuredClone(agent)] },
  });
  MarcosxAiAPI.getConnectionHealth.mockResolvedValue({
    data: { credentials: [], assistants: [structuredClone(agent)] },
  });
  global = {
    plugins: [
      router,
      createStore({
        getters: {
          getCurrentRole: () => 'administrator',
          'inboxes/getInboxes': () => [],
        },
        actions: { 'inboxes/get': () => {} },
      }),
    ],
    stubs: {
      AgentEditor: {
        props: ['agent'],
        template: '<div data-editor>{{ agent.name }}</div>',
      },
      PendingReplies: {
        template: '<button type="button">Pending picker</button>',
      },
    },
  };
  wrapper = mount({ template: '<router-view />' }, { global });
  await flushPromises();
});
afterEach(() => {
  wrapper.unmount();
  vi.useRealTimers();
});

it('opens configuration from the card description and returns to all agents through the sidebar URL', async () => {
  await wrapper.get('article p').trigger('click');
  await flushPromises();
  expect(wrapper.find('[data-editor]').exists()).toBe(true);
  expect(router.currentRoute.value.query.agent).toBe('1');
  await router.push('/app/accounts/1/captain/overview');
  await flushPromises();
  expect(wrapper.find('[data-editor]').exists()).toBe(false);
  expect(wrapper.get('article').text()).toContain(agent.name);
});

it('protects unsaved changes when returning through the sidebar and allows discard to complete the navigation', async () => {
  await wrapper.get('article').trigger('click');
  await flushPromises();
  wrapper.findComponent(AgentEditor).vm.$emit('dirtyChange', true);
  await router.push('/app/accounts/1/captain/overview');
  await flushPromises();
  expect(router.currentRoute.value.query.agent).toBe('1');
  expect(wrapper.find('[data-editor]').exists()).toBe(true);
  wrapper.findAllComponents(Dialog)[0].vm.$emit('confirm');
  await flushPromises();
  expect(router.currentRoute.value.query.agent).toBeUndefined();
  expect(wrapper.find('[data-editor]').exists()).toBe(false);
});

it('pauses active individual overrides even when the persisted manual-group setting was already off', async () => {
  MarcosxAiAPI.setManualSessions.mockResolvedValue({
    data: {
      assistant: {
        ...agent,
        manual_sessions_count: 0,
        manual_sessions_paused_count: 2,
      },
    },
  });
  const toggle = wrapper.findAll('article [role="switch"]')[1];
  expect(toggle.attributes('aria-checked')).toBe('true');
  await toggle.trigger('click');
  await flushPromises();
  expect(MarcosxAiAPI.setManualSessions).toHaveBeenCalledWith(1, false);
  expect(toggle.attributes('aria-checked')).toBe('false');
  expect(wrapper.find('[data-editor]').exists()).toBe(false);
  MarcosxAiAPI.setManualSessions.mockResolvedValue({
    data: { assistant: agent },
  });
  await toggle.trigger('click');
  await flushPromises();
  expect(MarcosxAiAPI.setManualSessions).toHaveBeenLastCalledWith(1, true);
});

it('opens manual attendance from its count without toggling the group or opening the default section', async () => {
  await wrapper
    .findAll('article button')
    .find(button => button.text().includes('MARCOX_AI.PENDING.MANUAL'))
    .trigger('click');
  await flushPromises();
  expect(router.currentRoute.value.query).toMatchObject({
    agent: '1',
    section: 'attendance',
    manual: 'true',
  });
  expect(MarcosxAiAPI.setManualSessions).not.toHaveBeenCalled();
});

it('keeps the confirmed active state after a failed pause', async () => {
  MarcosxAiAPI.setManualSessions.mockRejectedValue(new Error('Unavailable'));
  const toggle = wrapper.findAll('article [role="switch"]')[1];
  await toggle.trigger('click');
  await flushPromises();
  expect(toggle.attributes('aria-checked')).toBe('true');
  expect(toggle.attributes('disabled')).toBeUndefined();
  expect(wrapper.find('article').exists()).toBe(true);
});

it('keeps the manual filter when the real editor synchronizes its attendance section with the URL', async () => {
  wrapper.unmount();
  MarcosxAiAPI.getAssistantCoverage.mockResolvedValue({
    data: {
      mode: 'individual',
      total: 1,
      page: 1,
      conversations: [
        { id: 12, contact_name: 'Manual contact', inbox_name: 'Inbox' },
      ],
    },
  });
  wrapper = mount(
    { template: '<router-view />' },
    { global: { ...global, stubs: { ...global.stubs, AgentEditor: false } } }
  );
  await flushPromises();
  await wrapper
    .findAll('article button')
    .find(button => button.text().includes('MARCOX_AI.PENDING.MANUAL'))
    .trigger('click');
  await flushPromises();
  expect(router.currentRoute.value.query.manual).toBe('true');
  expect(wrapper.findComponent(AgentAttendance).props('manualOnly')).toBe(true);
  expect(wrapper.text()).toContain('Manual contact');
});

it('refreshes attendance counts without replacing an open draft', async () => {
  wrapper.unmount();
  vi.useFakeTimers();
  wrapper = mount({ template: '<router-view />' }, { global });
  await flushPromises();
  MarcosxAiAPI.getConnectionHealth.mockResolvedValue({
    data: {
      credentials: [],
      assistants: [
        { id: 1, manual_sessions_count: 3, manual_sessions_paused_count: 0 },
      ],
    },
  });
  await vi.advanceTimersByTimeAsync(10000);
  await flushPromises();
  expect(wrapper.get('article').text()).toContain('(3)');
  await wrapper.get('article').trigger('click');
  await flushPromises();
  const before = wrapper.findComponent(AgentEditor).props('agent');
  await vi.advanceTimersByTimeAsync(10000);
  await flushPromises();
  expect(wrapper.findComponent(AgentEditor).props('agent')).toEqual(before);
});
