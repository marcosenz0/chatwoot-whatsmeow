import { defineComponent } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import InboxesAPI from 'dashboard/api/inboxes';
import Button from 'next/button/Button.vue';
import GroupMember from '../GroupMember.vue';
import GroupMemberActions from '../GroupMemberActions.vue';

const { push, alert } = vi.hoisted(() => ({ push: vi.fn(), alert: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 2 }, name: 'conversation' }),
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alert }));
vi.mock('dashboard/api/inboxes', () => ({
  default: { createWhatsmeowDirectConversation: vi.fn() },
}));
const DialogStub = defineComponent({
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<div><slot /></div>',
});
const member = {
  jid: '123@lid',
  lid_jid: '123@lid',
  phone_number: '+15551111111',
  name: 'Saved contact',
  profile_picture_url: 'https://example.com/avatar.png',
};

beforeEach(() => {
  vi.clearAllMocks();
  Object.defineProperty(HTMLElement.prototype, 'showPopover', {
    value: vi.fn(),
    configurable: true,
  });
  Object.defineProperty(HTMLElement.prototype, 'hidePopover', {
    value: vi.fn(),
    configurable: true,
  });
});
afterAll(() => {
  delete HTMLElement.prototype.showPopover;
  delete HTMLElement.prototype.hidePopover;
});

it('selects the named member while keeping administrator controls separate', async () => {
  const wrapper = shallowMount(GroupMember, {
    props: { member, canManage: true },
  });
  await wrapper.get('button[aria-haspopup="menu"]').trigger('click');
  expect(wrapper.emitted('select')).toEqual([[member]]);
  expect(wrapper.text()).toContain('Saved contact');
  expect(wrapper.get('details').exists()).toBe(true);
  expect(wrapper.classes()).toContain('hover:bg-n-alpha-2');
  wrapper.unmount();
});

it('opens contact details and explains the unavailable security code', async () => {
  const wrapper = shallowMount(GroupMemberActions, {
    props: { inboxId: 28 },
    global: {
      stubs: {
        Dialog: DialogStub,
        Teleport: { template: '<div><slot /></div>' },
      },
    },
  });
  const menu = HTMLElement.prototype;
  await wrapper.setProps({ member });
  await flushPromises();
  expect(menu.showPopover).toHaveBeenCalledOnce();
  await wrapper.findAllComponents(Button)[0].trigger('click');
  expect(wrapper.text()).toContain('Saved contact');
  expect(wrapper.text()).toContain('+15551111111');
  await wrapper.findAllComponents(Button)[1].trigger('click');
  expect(wrapper.text()).toContain('WHATSMEOW_UI.SECURITY_CODE_HELP');
  expect(InboxesAPI.createWhatsmeowDirectConversation).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('opens a direct conversation with the selected identity and current inbox', async () => {
  InboxesAPI.createWhatsmeowDirectConversation.mockResolvedValue({
    data: { conversation_id: 77 },
  });
  const wrapper = shallowMount(GroupMemberActions, {
    props: { inboxId: 28 },
    global: {
      stubs: {
        Dialog: DialogStub,
        Teleport: { template: '<div><slot /></div>' },
      },
    },
  });
  await wrapper.setProps({ member });
  await wrapper.findAllComponents(Button)[2].trigger('click');
  await flushPromises();
  expect(InboxesAPI.createWhatsmeowDirectConversation).toHaveBeenCalledWith(
    28,
    {
      participant_jid: '123@lid',
      participant_lid_jid: '123@lid',
      participant_phone: '+15551111111',
      participant_name: 'Saved contact',
      profile_picture_url: 'https://example.com/avatar.png',
    }
  );
  expect(push).toHaveBeenCalledWith({
    path: '/app/accounts/2/inbox/28/conversations/77',
  });
  expect(wrapper.emitted('navigate')).toHaveLength(1);
  expect(alert).not.toHaveBeenCalled();
  wrapper.unmount();
});
