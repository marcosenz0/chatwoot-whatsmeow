import { flushPromises, mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import WhatsmeowStatusReplyPreview from '../WhatsmeowStatusReplyPreview.vue';

const mocks = vi.hoisted(() => ({
  preview: vi.fn(),
  useAlert: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: mocks.useAlert,
}));

vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: () => ({ value: { avatar_url: '' } }),
}));

vi.mock('dashboard/api/whatsmeowStatuses', () => ({
  default: { preview: mocks.preview },
}));

const mountPreview = () =>
  mount(WhatsmeowStatusReplyPreview, {
    props: { statusReply: { id: 321 } },
    global: {
      stubs: {
        Icon: true,
        Spinner: true,
        StatusViewer: true,
      },
    },
  });

describe('WhatsmeowStatusReplyPreview', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.preview.mockRejectedValue(new Error('Status unavailable'));
  });

  it('only alerts for an unavailable status after an explicit open attempt', async () => {
    const wrapper = mountPreview();
    await flushPromises();

    expect(mocks.preview).toHaveBeenCalledTimes(1);
    expect(mocks.useAlert).not.toHaveBeenCalled();

    await wrapper.get('button').trigger('click');
    await flushPromises();

    expect(mocks.preview).toHaveBeenCalledTimes(2);
    expect(mocks.useAlert).toHaveBeenCalledWith(
      'WHATSAPP_STATUS.REPLY_PREVIEW.UNAVAILABLE'
    );
  });
});
