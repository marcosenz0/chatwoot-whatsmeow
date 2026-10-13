import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ContextMenu from 'dashboard/modules/conversations/components/MessageContextMenu.vue';

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
  useTrack: vi.fn(),
}));

it('opens one canned-response form outside the transformed message rail and closes it without saving', async () => {
  const holder = document.createElement('div');
  holder.style.transform = 'translateY(-50%)';
  document.body.appendChild(holder);
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentRole: () => 'administrator',
      getUISettings: () => ({}),
      'inboxes/getInbox': () => () => ({}),
      'accounts/getAccount': () => () => ({ locale: 'en' }),
    },
  });
  const wrapper = mount(ContextMenu, {
    attachTo: holder,
    props: {
      message: {
        id: 3,
        conversation_id: 92,
        content: 'Reusable answer',
        message_type: 1,
      },
      isOpen: true,
      enabledOptions: { cannedResponse: true },
    },
    global: {
      plugins: [store],
      stubs: {
        'woot-delete-modal': true,
        ContextMenu: { template: '<div><slot /></div>' },
        MenuItem: {
          props: ['option'],
          template: '<button>{{ option.label }}</button>',
        },
        AddCannedModal: {
          props: ['responseContent', 'onClose'],
          template:
            '<section role="dialog"><p>{{ responseContent }}</p><button @click="onClose">Cancel</button></section>',
        },
      },
    },
  });
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('CREATE_A_CANNED_RESPONSE'))
    .trigger('click');
  await flushPromises();
  expect(document.querySelectorAll('[role="dialog"]')).toHaveLength(1);
  expect(holder.querySelector('[role="dialog"]')).toBeNull();
  const dialog = document.querySelector('[role="dialog"]');
  expect(dialog.textContent).toContain('Reusable answer');
  dialog.querySelector('button').click();
  await flushPromises();
  expect(document.querySelector('[role="dialog"]')).toBeNull();
  wrapper.unmount();
  holder.remove();
});
