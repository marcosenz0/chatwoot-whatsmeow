import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import InstagramMedia from '../InstagramMedia.vue';

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
  }),
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('Instagram shared media preview', () => {
  it('expands inside the gallery and restores the passive preview when closed', async () => {
    const wrapper = mount(InstagramMedia, {
      global: {
        stubs: {
          BaseBubble: { template: '<div><slot /></div>' },
          GalleryView: {
            template:
              '<button class="close-gallery" @click="$emit(\'close\')">Close</button>',
          },
          Icon: true,
        },
      },
    });

    expect(wrapper.get('iframe').attributes('src')).toBe(
      'https://www.instagram.com/reel/AbC123/embed/'
    );
    expect(wrapper.get('iframe').classes()).toContain('pointer-events-none');
    expect(wrapper.get('a').attributes('href')).toBe(
      'https://www.instagram.com/reel/AbC123/'
    );
    await wrapper.get('button').trigger('click');
    expect(wrapper.find('iframe').exists()).toBe(false);
    expect(wrapper.find('.close-gallery').exists()).toBe(true);
    await wrapper.get('.close-gallery').trigger('click');
    expect(wrapper.find('iframe').exists()).toBe(true);
  });
});
