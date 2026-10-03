import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import InstagramMedia from '../InstagramMedia.vue';

const { showLink } = vi.hoisted(() => ({ showLink: { value: false } }));
vi.mock('../../provider.js', () => ({
  useMessageContext: () => ({
    attachments: ref([
      {
        id: 1,
        fileType: 'ig_reel',
        dataUrl: 'https://www.instagram.com/reel/AbC123/',
      },
    ]),
    filteredCurrentChatAttachments: ref([]),
    conversationId: ref(1),
    id: ref(7),
    instagramPreview: ref({
      permalink: 'https://www.instagram.com/reel/AbC123/',
    }),
    showInstagramLink: ref(showLink.value),
  }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const stubs = {
  BaseBubble: { template: '<div><slot /></div>' },
  InstagramPreview: {
    template:
      '<button class="expand" @click="$emit(\'expand\')">Expand</button>',
  },
  GalleryView: {
    template:
      '<button class="close-gallery" @click="$emit(\'close\')">Close</button>',
  },
};
describe('Instagram shared media preview', () => {
  beforeEach(() => {
    showLink.value = false;
  });
  it('opens the native gallery and restores the card after closing', async () => {
    const wrapper = mount(InstagramMedia, { global: { stubs } });
    expect(wrapper.find('iframe').exists()).toBe(false);
    await wrapper.get('.expand').trigger('click');
    expect(wrapper.find('.close-gallery').exists()).toBe(true);
    expect(wrapper.find('.expand').exists()).toBe(false);
    await wrapper.get('.close-gallery').trigger('click');
    expect(wrapper.find('.expand').exists()).toBe(true);
  });
  it('shows the canonical original link in link mode', () => {
    showLink.value = true;
    const wrapper = mount(InstagramMedia, { global: { stubs } });
    expect(wrapper.get('a').attributes('href')).toBe(
      'https://www.instagram.com/reel/AbC123/'
    );
    expect(wrapper.get('a').text()).toBe(
      'https://www.instagram.com/reel/AbC123/'
    );
    expect(wrapper.find('.expand').exists()).toBe(false);
  });
});
