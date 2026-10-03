import { mount, flushPromises } from '@vue/test-utils';
import MessageAPI from 'dashboard/api/inbox/message';
import InstagramPreview from '../InstagramPreview.vue';

vi.mock('dashboard/api/inbox/message', () => ({
  default: { instagramPreview: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const props = {
  url: 'https://www.instagram.com/reel/AbC123/',
  conversationId: 1,
  messageId: 7,
};
const global = { stubs: { Icon: true } };

describe('Native Instagram cards', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });
  it('uses native controls when Instagram supplies a video source', async () => {
    MessageAPI.instagramPreview.mockResolvedValue({
      data: { video_url: 'https://video.cdninstagram.com/reel.mp4' },
    });
    const wrapper = mount(InstagramPreview, { props, global });
    await flushPromises();
    expect(wrapper.get('video').attributes('controls')).toBeDefined();
    expect(wrapper.get('video').attributes('src')).toBe(
      'https://video.cdninstagram.com/reel.mp4'
    );
    expect(wrapper.find('iframe').exists()).toBe(false);
  });
  it('recovers a cover in the app theme and expands it without a passive iframe', async () => {
    MessageAPI.instagramPreview.mockResolvedValue({
      data: {
        image_url: 'https://scontent.cdninstagram.com/cover.jpg',
        status: 'available',
      },
    });
    const wrapper = mount(InstagramPreview, { props, global });
    await flushPromises();
    expect(wrapper.get('section').classes()).toContain('bg-n-background');
    expect(wrapper.get('img').attributes('src')).toContain('cover.jpg');
    expect(wrapper.find('iframe').exists()).toBe(false);
    await wrapper
      .get('button[aria-label="GALLERY_VIEW.EXPAND"]')
      .trigger('click');
    expect(wrapper.emitted('expand')).toHaveLength(1);
  });
  it('keeps a blocked profile link usable without claiming it was deleted', async () => {
    MessageAPI.instagramPreview.mockRejectedValue(new Error('blocked'));
    const wrapper = mount(InstagramPreview, {
      props: { ...props, url: 'https://instagram.com/example.user/' },
      global,
    });
    await flushPromises();
    expect(wrapper.text()).toContain('example.user');
    expect(wrapper.text()).toContain('INSTAGRAM_PREVIEW.PROFILE_LIMIT');
    expect(wrapper.get('a').attributes('href')).toBe(
      'https://www.instagram.com/example.user/'
    );
  });
  it('renders actual profile data and emits the selected photo for expansion', async () => {
    const post = {
      url: 'https://www.instagram.com/p/post123/',
      image_url: 'https://scontent.cdninstagram.com/post.jpg',
    };
    MessageAPI.instagramPreview.mockResolvedValue({
      data: {
        username: 'example.user',
        bio: 'Example bio',
        posts: [post],
        status: 'available',
      },
    });
    const wrapper = mount(InstagramPreview, {
      props: { ...props, url: 'https://instagram.com/example.user/' },
      global,
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Example bio');
    await wrapper.get('.grid.grid-cols-3 button').trigger('click');
    expect(wrapper.emitted('expand')[0]).toEqual([post]);
  });
  it('offers the provider player explicitly when a direct source is absent', async () => {
    MessageAPI.instagramPreview.mockResolvedValue({
      data: { status: 'limited' },
    });
    const wrapper = mount(InstagramPreview, {
      props: { ...props, expanded: true },
      global,
    });
    await flushPromises();
    expect(wrapper.find('iframe').exists()).toBe(false);
    await wrapper.get('button[aria-expanded]').trigger('click');
    expect(wrapper.get('iframe').attributes('scrolling')).toBe('no');
    expect(wrapper.get('iframe').attributes('src')).toBe(
      'https://www.instagram.com/reel/AbC123/embed/'
    );
  });
});
