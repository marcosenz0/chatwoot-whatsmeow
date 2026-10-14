import { ref } from 'vue';
import { createStore } from 'vuex';
import { flushPromises, mount } from '@vue/test-utils';
import WhatsappProfileAPI from 'dashboard/api/whatsappProfile';
import Audio from '../chips/Audio.vue';
import { ORIENTATION } from '../constants';

vi.mock('dashboard/api/whatsappProfile', () => ({
  default: { photo: vi.fn() },
}));
const context = {
  contentAttributes: ref({ whatsmeow_recorded_audio: true }),
  conversationId: ref(92),
  id: ref(10),
  inboxId: ref(88),
  orientation: ref(ORIENTATION.RIGHT),
  sender: ref({ id: 1, name: 'Agent', thumbnail: 'agent.png' }),
};
vi.mock('../provider.js', () => ({ useMessageContext: () => context }));
const store = createStore({
  getters: {
    'inboxes/getInbox': () => () => ({
      channel_type: 'Channel::Whatsmeow',
      name: 'Connected instance',
    }),
    getCurrentAccountId: () => 1,
  },
});
const options = {
  props: {
    attachment: {
      id: 9,
      dataUrl: '',
      meta: {
        transcribed_text: 'A long transcript '.repeat(30),
        waveform: [1, 3, 6, 2],
      },
    },
  },
  global: {
    plugins: [store],
    stubs: {
      ProfilePhotoAvatar: {
        props: ['src', 'name'],
        template: '<img :src="src" :alt="name" />',
      },
      MessageMeta: true,
    },
  },
};

describe('Recorded audio layout and identity', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    context.orientation.value = ORIENTATION.RIGHT;
    WhatsappProfileAPI.photo.mockResolvedValue({
      data: { photo_url: 'instance.png' },
    });
  });

  it('uses the connected inbox photo for outgoing audio and shares a single photo request across bubbles', async () => {
    const first = mount(Audio, options);
    const second = mount(Audio, options);
    await flushPromises();
    expect(first.get('img').attributes('src')).toBe('instance.png');
    expect(second.get('img').attributes('alt')).toBe('Connected instance');
    expect(WhatsappProfileAPI.photo).toHaveBeenCalledTimes(1);
    first.unmount();
    second.unmount();
  });

  it('keeps the same compact waveform and player after opening a much wider transcript', async () => {
    const wrapper = mount(Audio, options);
    await flushPromises();
    const waveform = wrapper.get('[data-testid="audio-waveform"]');
    const bars = waveform.findAll('span');
    expect(bars).toHaveLength(48);
    expect(bars.every(bar => bar.classes().includes('max-w-0.5'))).toBe(true);
    const before = waveform.html();
    await wrapper
      .findAll('button')
      .find(button => /TRANSCRIBE|Transcri/i.test(button.text()))
      .trigger('click');
    expect(wrapper.text()).toContain('A long transcript');
    expect(wrapper.get('[data-testid="audio-waveform"]').html()).toBe(before);
    expect(
      waveform.element.parentElement.parentElement.parentElement.classList.contains(
        'w-80'
      )
    ).toBe(true);
    wrapper.unmount();
  });

  it('keeps the actual contact avatar on incoming audio', async () => {
    context.orientation.value = ORIENTATION.LEFT;
    const wrapper = mount(Audio, options);
    await flushPromises();
    expect(wrapper.get('img').attributes('src')).toBe('agent.png');
    expect(WhatsappProfileAPI.photo).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('preserves sender avatars on other channels that have no own WhatsApp profile endpoint', async () => {
    const otherStore = createStore({
      getters: {
        'inboxes/getInbox': () => () => ({
          channel_type: 'Channel::TelegramPersonal',
          name: 'Telegram inbox',
        }),
        getCurrentAccountId: () => 1,
      },
    });
    const wrapper = mount(Audio, {
      ...options,
      global: { ...options.global, plugins: [otherStore] },
    });
    await flushPromises();
    expect(wrapper.get('img').attributes('src')).toBe('agent.png');
    expect(WhatsappProfileAPI.photo).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
