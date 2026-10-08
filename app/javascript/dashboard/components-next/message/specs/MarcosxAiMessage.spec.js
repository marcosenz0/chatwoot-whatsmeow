import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Message from '../Message.vue';
import { SENDER_TYPES } from '../constants';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 }, query: {} }),
}));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: value => value }),
}));
const props = {
  id: 9,
  messageType: 1,
  status: 'sent',
  conversationId: 7,
  createdAt: 1720000000,
  currentUserId: 2,
  inboxId: 3,
  content: 'Hello',
};
const store = createStore({
  getters: {
    'inboxes/getInbox': () => () => ({ channel_type: 'Channel::Whatsmeow' }),
    'globalConfig/isOnChatwootCloud': () => false,
  },
});

describe('MarcoXIA message ownership', () => {
  it('aligns AI replies with outgoing team messages', () => {
    const wrapper = shallowMount(Message, {
      props: {
        ...props,
        sender: { id: 1, name: 'Felipe', type: SENDER_TYPES.MARCOX_ASSISTANT },
      },
      global: { plugins: [store] },
    });
    expect(wrapper.classes()).toContain('justify-end');
    expect(wrapper.classes()).not.toContain('justify-start');
    wrapper.unmount();
  });
  it('keeps customer messages on the opposite side', () => {
    const wrapper = shallowMount(Message, {
      props: {
        ...props,
        messageType: 0,
        sender: { id: 5, name: 'Customer', type: 'contact' },
      },
      global: { plugins: [store] },
    });
    expect(wrapper.classes()).toContain('justify-start');
    wrapper.unmount();
  });
});
