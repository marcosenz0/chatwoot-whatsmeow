import { flushPromises, mount } from '@vue/test-utils';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import ConversationItem from '../ConversationItem.vue';

const { store, open } = vi.hoisted(() => ({
  store: {
    commit: vi.fn(),
    getters: {
      'conversationTypingStatus/getUserList': () => [],
      'contacts/getContact': () => ({ name: 'Owner' }),
      'inboxes/getInbox': () => ({ id: 27 }),
    },
  },
  open: vi.fn(),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => store,
  useMapGetter: key => ({
    value: {
      getSelectedChat: { id: 1 },
      'inboxes/getInboxes': [],
      getSelectedInbox: null,
      getCurrentAccountId: 2,
    }[key],
  }),
}));
vi.mock('dashboard/api/marcosxAi', () => ({
  default: { getConversationState: vi.fn() },
}));
vi.mock('../widgets/conversation/ConversationAiPanel.vue', () => ({
  default: {
    name: 'ConversationAiPanel',
    props: ['chat', 'state', 'assistants'],
    setup(_, { expose }) {
      expose({ open });
    },
    template: '<div class="ai-panel" />',
  },
}));
const props = {
  source: {
    id: 7,
    status: 'open',
    inbox_id: 27,
    meta: { sender: { id: 30 } },
    labels: [],
  },
};
const global = {
  provide: {
    toggleContextMenu: vi.fn(),
    isConversationSelected: () => false,
  },
  stubs: {
    ConversationCard: {
      template:
        '<button class="card" @contextmenu="$emit(\'contextmenu\', $event)">Conversation</button>',
    },
    ContextMenu: { template: '<div><slot /></div>' },
    ConversationContextMenu: {
      template:
        '<button class="generate" @click="$emit(\'generateAiReply\')">Generate</button>',
    },
  },
};
describe('AI reply from a conversation context menu', () => {
  it('keeps the fetched activation when an older conversation event arrives', async () => {
    const state = {
      assistant_id: 1,
      status: 'active',
      enabled: true,
      available: true,
      updated_at: '2026-10-08T23:25:56.908Z',
    };
    MarcosxAiAPI.getConversationState.mockResolvedValue({
      data: { state, assistants: [{ id: 1 }] },
    });
    const wrapper = mount(ConversationItem, { props, global });
    await wrapper.get('.card').trigger('contextmenu');
    await wrapper.get('.generate').trigger('click');
    await flushPromises();
    await wrapper.setProps({
      source: {
        ...props.source,
        marcosx_ai: {
          ...state,
          status: 'paused_by_agent',
          updated_at: '2026-10-08T23:24:00.000Z',
        },
      },
    });
    expect(
      wrapper.findComponent({ name: 'ConversationAiPanel' }).props('state')
    ).toEqual(state);
    wrapper.unmount();
  });
  it('opens the same review panel for the clicked row without activating or sending', async () => {
    const state = { assistant_id: 1, status: 'paused_by_agent' };
    MarcosxAiAPI.getConversationState.mockResolvedValue({
      data: { state, assistants: [{ id: 1 }] },
    });
    const wrapper = mount(ConversationItem, { props, global });
    await wrapper.get('.card').trigger('contextmenu');
    await wrapper.get('.generate').trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.getConversationState).toHaveBeenCalledWith(7);
    expect(open).toHaveBeenCalledOnce();
    expect(
      wrapper.findComponent({ name: 'ConversationAiPanel' }).props('chat').id
    ).toBe(7);
    expect(wrapper.find('.generate').exists()).toBe(false);
    wrapper.unmount();
  });
  it('ignores a late response when the virtual row is recycled', async () => {
    let finish;
    MarcosxAiAPI.getConversationState.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount(ConversationItem, { props, global });
    await wrapper.get('.card').trigger('contextmenu');
    await wrapper.get('.generate').trigger('click');
    await wrapper.setProps({ source: { ...props.source, id: 8 } });
    finish({ data: { state: null, assistants: [] } });
    await flushPromises();
    expect(open).not.toHaveBeenCalled();
    expect(wrapper.find('.ai-panel').exists()).toBe(false);
    wrapper.unmount();
  });
});
