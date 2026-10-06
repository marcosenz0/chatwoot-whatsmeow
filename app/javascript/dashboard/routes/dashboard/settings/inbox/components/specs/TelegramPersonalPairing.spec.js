import { mount, flushPromises } from '@vue/test-utils';
import InboxesAPI from 'dashboard/api/inboxes';
import TelegramPersonalPairing from '../TelegramPersonalPairing.vue';

vi.mock('dashboard/api/inboxes', () => ({
  default: {
    getTelegramPersonalStatus: vi.fn(),
    connectTelegramPersonal: vi.fn(),
    disconnectTelegramPersonal: vi.fn(),
    submitTelegramPersonalPassword: vi.fn(),
  },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const options = {
  props: { inboxId: 7 },
  global: {
    stubs: {
      NextButton: {
        template:
          '<button :type="type" @click="$emit(\'click\')">{{ label }}</button>',
        props: ['label', 'type'],
      },
    },
  },
};

describe('Telegram account pairing', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    InboxesAPI.getTelegramPersonalStatus.mockResolvedValue({
      data: { status: 'disconnected' },
    });
  });
  afterEach(() => vi.useRealTimers());

  it('pairs this inbox and clears the QR when connected', async () => {
    const wrapper = mount(TelegramPersonalPairing, options);
    await flushPromises();
    InboxesAPI.connectTelegramPersonal.mockResolvedValue({
      data: {
        status: 'qr',
        qr_code: 'data:image/png;base64,test',
        expires_at: Date.now() / 1000 + 30,
      },
    });
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(InboxesAPI.connectTelegramPersonal).toHaveBeenCalledWith(7);
    expect(wrapper.find('img').exists()).toBe(true);
    InboxesAPI.getTelegramPersonalStatus.mockResolvedValue({
      data: { status: 'connected', username: 'test' },
    });
    await vi.advanceTimersByTimeAsync(3000);
    await flushPromises();
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.emitted('connected')).toHaveLength(1);
    expect(wrapper.text()).toContain('@test');
    wrapper.unmount();
  });

  it('never displays an expired QR code', async () => {
    InboxesAPI.getTelegramPersonalStatus.mockResolvedValue({
      data: {
        status: 'qr',
        qr_code: 'expired',
        expires_at: Date.now() / 1000 - 1,
      },
    });
    const wrapper = mount(TelegramPersonalPairing, options);
    await flushPromises();
    expect(wrapper.find('img').exists()).toBe(false);
    wrapper.unmount();
  });

  it('removes the QR and reports a service failure when polling fails', async () => {
    InboxesAPI.getTelegramPersonalStatus.mockResolvedValue({
      data: {
        status: 'qr',
        qr_code: 'secret',
        expires_at: Date.now() / 1000 + 30,
      },
    });
    const wrapper = mount(TelegramPersonalPairing, options);
    await flushPromises();
    InboxesAPI.getTelegramPersonalStatus.mockRejectedValue(
      new Error('offline')
    );
    await vi.advanceTimersByTimeAsync(3000);
    await flushPromises();
    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'service_unavailable'
    );
    wrapper.unmount();
  });

  it('submits the two-step password only to this inbox and clears the input', async () => {
    InboxesAPI.getTelegramPersonalStatus.mockResolvedValue({
      data: { status: 'password' },
    });
    InboxesAPI.submitTelegramPersonalPassword.mockResolvedValue({
      data: { status: 'password' },
    });
    const wrapper = mount(TelegramPersonalPairing, options);
    await flushPromises();
    await wrapper.find('input').setValue('test-password');
    await wrapper.find('form').trigger('submit.prevent');
    await flushPromises();
    expect(InboxesAPI.submitTelegramPersonalPassword).toHaveBeenCalledWith(
      7,
      'test-password'
    );
    expect(wrapper.find('input').element.value).toBe('');
    wrapper.unmount();
  });

  it('stops polling after navigating away', async () => {
    const wrapper = mount(TelegramPersonalPairing, options);
    await flushPromises();
    wrapper.unmount();
    await vi.advanceTimersByTimeAsync(9000);
    expect(InboxesAPI.getTelegramPersonalStatus).toHaveBeenCalledTimes(1);
  });
});
