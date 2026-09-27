import { mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import WhatsmeowPixCard from '../WhatsmeowPixCard.vue';

const mocks = vi.hoisted(() => ({ useAlert: vi.fn() }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.useAlert,
}));

describe('WhatsmeowPixCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows the recipient, type and Pix key in a copyable card', async () => {
    const writeText = vi.fn().mockResolvedValue();
    vi.stubGlobal('navigator', {
      ...navigator,
      clipboard: { writeText },
    });

    const wrapper = mount(WhatsmeowPixCard, {
      props: {
        pix: {
          key_type: 'EMAIL',
          key: 'payments@example.com',
          merchant_name: 'Example Store',
        },
      },
      global: { stubs: { Icon: true, PixIcon: true } },
    });

    expect(wrapper.text()).toContain('Example Store');
    expect(wrapper.text()).toContain('payments@example.com');
    expect(wrapper.text()).toContain(
      'CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.EMAIL'
    );

    await wrapper.get('button').trigger('click');

    expect(writeText).toHaveBeenCalledWith('payments@example.com');
    expect(mocks.useAlert).toHaveBeenCalledWith(
      'CONVERSATION.WHATSMEOW_PIX.COPIED'
    );

    vi.unstubAllGlobals();
  });
});
