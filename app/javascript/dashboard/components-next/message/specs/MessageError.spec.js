import { mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import MessageError from '../MessageError.vue';

const mocks = vi.hoisted(() => ({
  context: {
    orientation: { value: 'right' },
    status: { value: 'failed' },
    createdAt: { value: Date.now() / 1000 },
    content: { value: 'Pix key' },
    attachments: { value: [] },
    contentAttributes: { value: {} },
  },
}));

vi.mock('../provider.js', () => ({
  useMessageContext: () => mocks.context,
}));

vi.mock('shared/helpers/timeHelper', () => ({
  hasOneDayPassed: () => false,
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

describe('MessageError', () => {
  beforeEach(() => {
    mocks.context.contentAttributes.value = {};
  });

  it.each(['whatsmeowPix', 'whatsmeow_pix'])(
    'does not offer generic retry for a %s card',
    pixAttribute => {
      mocks.context.contentAttributes.value = {
        [pixAttribute]: { key: 'key' },
      };

      const wrapper = mount(MessageError, {
        props: { error: 'Delivery failed' },
        global: { stubs: { Icon: true } },
      });

      expect(wrapper.findAll('button')).toHaveLength(1);
      expect(wrapper.text()).toContain(
        'CONVERSATION.WHATSMEOW_PIX.RETRY_UNAVAILABLE'
      );
    }
  );

  it('still offers generic retry for an ordinary message', () => {
    const wrapper = mount(MessageError, {
      props: { error: 'Delivery failed' },
      global: { stubs: { Icon: true } },
    });

    expect(wrapper.findAll('button')).toHaveLength(2);
  });
});
