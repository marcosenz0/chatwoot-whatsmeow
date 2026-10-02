import { defineComponent, ref } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import GroupsAPI from 'dashboard/api/whatsmeowGroups';
import Button from 'next/button/Button.vue';
import Input from 'next/input/Input.vue';
import GroupPanel from '../GroupPanel.vue';
import GroupMember from '../GroupMember.vue';

vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({ getters: { getCurrentAccountId: 2 }, dispatch: vi.fn() }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ updateUISettings: vi.fn(), uiSettings: ref({}) }),
}));
vi.mock('dashboard/composables/useWhatsmeowPreferences', () => ({
  useWhatsmeowPreferences: () => ({ set: vi.fn() }),
}));
vi.mock('dashboard/composables/emitter', () => ({ useEmitter: vi.fn() }));
vi.mock('dashboard/api/whatsmeowGroups', () => ({
  default: { show: vi.fn() },
}));

const DialogStub = defineComponent({
  emits: ['close'],
  setup(_, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
        emit('close');
      },
    });
    return { visible };
  },
  template: '<div v-if="visible"><slot /></div>',
});
const chat = {
  id: 1,
  inbox_id: 28,
  meta: {
    sender: {
      thumbnail: '',
      additional_attributes: { group_jid: 'test@g.us' },
    },
  },
};
const roster = [
  ...Array.from({ length: 15 }, (_, index) => ({
    jid: `member-${index}`,
    name: `Member ${index}`,
    phone_number: `1555000${index}`,
  })),
  { jid: 'self', name: 'Self', phone_number: '15551111111', is_self: true },
  { jid: 'admin', name: 'Admin', phone_number: '15552222222', is_admin: true },
  {
    jid: 'owner',
    name: 'Owner',
    phone_number: '15553333333',
    is_super_admin: true,
  },
];

beforeEach(() => {
  GroupsAPI.show.mockResolvedValue({
    data: {
      members: roster,
      count: roster.length,
      group_name: 'Test',
      topic: '',
      created_at: 1,
      disappearing_timer: 0,
      can_edit: false,
      self_is_admin: false,
    },
  });
});

it('keeps nine members in the sidebar while searching and closing the full roster', async () => {
  const wrapper = shallowMount(GroupPanel, {
    props: { chat },
    global: { stubs: { Dialog: DialogStub } },
  });
  await flushPromises();
  expect(wrapper.findAllComponents(GroupMember)).toHaveLength(9);
  expect(
    wrapper
      .findAllComponents(GroupMember)
      .slice(0, 3)
      .map(member => member.props('member').jid)
  ).toEqual(['owner', 'admin', 'self']);
  const viewAll = wrapper
    .findAllComponents(Button)
    .find(button => button.props('label') === 'WHATSMEOW_UI.VIEW_ALL_MEMBERS');
  await viewAll.trigger('click');
  expect(
    wrapper.get('[data-group-members-list]').findAllComponents(GroupMember)
  ).toHaveLength(18);
  await wrapper
    .getComponent(Input)
    .vm.$emit('update:modelValue', '15552222222');
  await flushPromises();
  expect(
    wrapper
      .get('[data-group-members-list]')
      .findAllComponents(GroupMember)
      .map(member => member.props('member').jid)
  ).toEqual(['admin']);
  wrapper.getComponent(DialogStub).vm.close();
  await flushPromises();
  expect(wrapper.findAllComponents(GroupMember)).toHaveLength(9);
  expect(wrapper.find('[data-group-members-list]').exists()).toBe(false);
  wrapper.unmount();
});
