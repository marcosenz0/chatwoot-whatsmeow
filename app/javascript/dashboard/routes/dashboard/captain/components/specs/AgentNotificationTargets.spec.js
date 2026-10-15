import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/marcosxAi';
import AgentNotificationTargets from '../AgentNotificationTargets.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: {
    getNotificationTargets: vi.fn(),
    getNotificationOptions: vi.fn(),
    saveNotificationTarget: vi.fn(),
    deleteNotificationTarget: vi.fn(),
  },
}));
const global = {
  stubs: {
    Dialog: {
      props: ['disableConfirmButton'],
      setup(_, { expose }) {
        const visible = ref(false);
        expose({
          open() {
            visible.value = true;
          },
          close() {
            visible.value = false;
          },
        });
        return { visible };
      },
      template:
        '<form v-if="visible" @submit.prevent="$emit(\'confirm\')"><slot /></form>',
    },
  },
};
beforeEach(() => {
  vi.clearAllMocks();
  API.getNotificationTargets.mockResolvedValue({
    data: { notification_targets: [] },
  });
  API.getNotificationOptions.mockResolvedValue({
    data: { inboxes: [{ id: 4, name: 'WhatsApp' }] },
  });
  API.saveNotificationTarget.mockResolvedValue({
    data: { notification_targets: [] },
  });
});

it('saves a quick notice number for only the selected conversation without sending a test notice', async () => {
  const wrapper = mount(AgentNotificationTargets, {
    props: {
      agentId: 1,
      conversationId: 92,
      globalScope: false,
      compact: true,
    },
    global,
  });
  await flushPromises();
  wrapper.vm.openCreate();
  await flushPromises();
  await wrapper.findAll('input')[0].setValue('Owner');
  await wrapper.findAll('input')[1].setValue('+15555550101');
  await wrapper.findAll('form')[0].trigger('submit');
  await flushPromises();
  expect(API.saveNotificationTarget).toHaveBeenCalledWith(1, undefined, {
    title: 'Owner',
    number: '+15555550101',
    inbox_id: 4,
    enabled: true,
    audience: 'conversation',
    conversation_id: 92,
    contact_ids: [],
  });
  expect(wrapper.emitted('saved')).toHaveLength(1);
  wrapper.unmount();
});

it('keeps existing contact restrictions when editing a notice from the full agent tab', async () => {
  const item = {
    id: 5,
    title: 'Owner',
    number: '+15555550101',
    inbox_id: 4,
    enabled: true,
    audience: 'conversation',
    conversation_id: 92,
    contact_ids: [],
  };
  API.getNotificationTargets.mockResolvedValue({
    data: { notification_targets: [item] },
  });
  const wrapper = mount(AgentNotificationTargets, {
    props: { agentId: 1 },
    global,
  });
  await flushPromises();
  expect(wrapper.text()).toContain('MARCOX_AI.AUDIENCE.BADGE_CONVERSATION');
  await wrapper
    .get('[aria-label="MARCOX_AI.NOTIFICATION_TARGETS.EDIT"]')
    .trigger('click');
  await wrapper.findAll('form')[0].trigger('submit');
  await flushPromises();
  expect(API.saveNotificationTarget).toHaveBeenCalledWith(
    1,
    5,
    expect.objectContaining({ audience: 'conversation', conversation_id: 92 })
  );
  wrapper.unmount();
});
