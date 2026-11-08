import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import Message from '../Message.vue';
import ImageBubble from '../bubbles/Image.vue';
import VideoBubble from '../bubbles/Video.vue';
import StickerBubble from '../bubbles/Sticker.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 }, query: {} }),
}));

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: value => value }),
}));

const store = createStore({
  getters: {
    'inboxes/getInbox': () => () => ({ channel_type: 'Channel::Whatsmeow' }),
    'globalConfig/isOnChatwootCloud': () => false,
  },
});

describe('Conversation media presentation', () => {
  it.each([
    ['photo', [{ fileType: 'image' }], 'Photo caption', ImageBubble],
    ['video', [{ fileType: 'video' }], 'Video caption', VideoBubble],
    [
      'image album',
      [{ fileType: 'image' }, { fileType: 'image' }],
      'Album caption',
      ImageBubble,
    ],
    [
      'sticker',
      [{ fileType: 'image', meta: { whatsmeowSticker: true } }],
      '',
      StickerBubble,
    ],
  ])(
    'uses the dedicated bubble for a %s',
    (_, attachments, content, bubble) => {
      const wrapper = shallowMount(Message, {
        props: {
          id: 9,
          messageType: 0,
          status: 'sent',
          conversationId: 7,
          createdAt: 1720000000,
          currentUserId: 2,
          inboxId: 3,
          sender: { id: 5, name: 'Customer', type: 'contact' },
          attachments,
          content,
        },
        global: { plugins: [store], stubs: { 'fluent-icon': true } },
      });
      expect(wrapper.findComponent(bubble).exists()).toBe(true);
      wrapper.unmount();
    }
  );
});
