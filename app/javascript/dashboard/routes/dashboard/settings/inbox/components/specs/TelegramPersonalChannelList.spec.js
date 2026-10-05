import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import messages from 'dashboard/i18n';
import ChannelList from '../../ChannelList.vue';

const mocks = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: mocks.push }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref({}),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(1),
    currentAccount: ref({ features: { channel_website: true } }),
    isOnChatwootCloud: ref(false),
  }),
}));

describe('Telegram personal inbox creation entry', () => {
  beforeEach(() => {
    window.chatwootConfig = { telegramPersonalEnabled: true };
  });

  afterEach(() => {
    delete window.chatwootConfig;
  });

  it.each(['en', 'pt_BR'])(
    'loads the %s production translations and opens the enabled personal account form',
    async locale => {
      const wrapper = mount(ChannelList, {
        global: {
          plugins: [createI18n({ legacy: false, locale, messages })],
          stubs: { Icon: true, Label: true },
        },
      });
      const title = messages[locale].TELEGRAM_PERSONAL.TITLE;
      const button = wrapper
        .findAll('button')
        .find(item => item.text().includes(title));
      expect(button).toBeDefined();
      expect(button.element.disabled).toBe(false);
      expect(button.text()).toContain(
        messages[locale].TELEGRAM_PERSONAL.DESCRIPTION
      );
      expect(wrapper.text()).not.toContain('TELEGRAM_PERSONAL.');
      await button.trigger('click');
      expect(mocks.push).toHaveBeenCalledWith({
        name: 'settings_inboxes_page_channel',
        params: { sub_page: 'telegram_personal', accountId: 1 },
      });
      wrapper.unmount();
    }
  );

  it('does not offer the personal account channel when the server bridge is disabled', () => {
    window.chatwootConfig.telegramPersonalEnabled = false;
    const wrapper = mount(ChannelList, {
      global: {
        plugins: [createI18n({ legacy: false, locale: 'pt_BR', messages })],
        stubs: { Icon: true, Label: true },
      },
    });
    expect(wrapper.text()).not.toContain(
      messages.pt_BR.TELEGRAM_PERSONAL.TITLE
    );
    wrapper.unmount();
  });
});
