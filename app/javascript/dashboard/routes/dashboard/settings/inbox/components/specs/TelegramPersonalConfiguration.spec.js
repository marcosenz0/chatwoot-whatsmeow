import { mount, flushPromises } from '@vue/test-utils';
import Configuration from '../../settingsPage/TelegramPersonalConfiguration.vue';

const mocks = vi.hoisted(() => ({ dispatch: vi.fn(), alert: vi.fn() }));
vi.mock('vuex', () => ({ useStore: () => ({ dispatch: mocks.dispatch }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));

const inbox = {
  id: 7,
  ignore_groups: true,
  ignore_channels: true,
  hide_groups: true,
  hide_channels: true,
};
const createWrapper = () =>
  mount(Configuration, {
    props: { inbox },
    global: {
      stubs: {
        TelegramPersonalPairing: true,
        NextButton: { template: '<button type="submit">Save</button>' },
      },
    },
  });

describe('Telegram group and channel settings', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.dispatch.mockResolvedValue({});
  });

  it('saves independent import and visibility choices for the correct inbox', async () => {
    const wrapper = createWrapper();
    const inputs = wrapper.findAll('input');
    await inputs[0].setValue(false);
    await inputs[3].setValue(false);
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(mocks.dispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: 7,
      channel: {
        ignore_groups: false,
        ignore_channels: true,
        hide_groups: true,
        hide_channels: false,
      },
    });
    expect(mocks.alert).toHaveBeenCalledWith('TELEGRAM_PERSONAL.SAVED');
  });

  it('refreshes checked controls when saved inbox data changes', async () => {
    const wrapper = createWrapper();
    await wrapper.setProps({ inbox: { ...inbox, hide_groups: false } });
    expect(
      wrapper.findAll('input').map(input => input.element.checked)
    ).toEqual([true, true, false, true]);
  });

  it('reports failed saves without claiming success', async () => {
    mocks.dispatch.mockRejectedValue(new Error('offline'));
    const wrapper = createWrapper();
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(mocks.alert).toHaveBeenCalledWith(
      'TELEGRAM_PERSONAL.ERRORS.service_unavailable'
    );
    expect(wrapper.vm.busy).toBe(false);
  });
});
