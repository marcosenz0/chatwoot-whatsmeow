import { mount } from '@vue/test-utils';

import AttachmentsPreview from '../AttachmentsPreview.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const audioAttachment = {
  id: 1,
  resource: {
    filename: 'voice.mp3',
    content_type: 'audio/mpeg',
    byte_size: 1024,
  },
};

const mountComponent = (attachments, allowRecordedAudio = true) =>
  mount(AttachmentsPreview, {
    props: { attachments, allowRecordedAudio },
  });

describe('AttachmentsPreview', () => {
  it('renders audio files with an audio icon and recorded-audio toggle', async () => {
    const wrapper = mountComponent([audioAttachment]);

    expect(wrapper.findComponent(Icon).props('icon')).toBe(
      'i-lucide-audio-lines'
    );

    const toggle = wrapper.find(
      '[aria-label="Send as recorded voice message"]'
    );
    expect(toggle.attributes('aria-pressed')).toBe('false');
    expect(toggle.text()).toBe('Send as recorded voice message');

    await toggle.trigger('click');

    expect(wrapper.emitted('toggleRecordedAudio')).toEqual([[0]]);
  });

  it('shows the active state when the audio will be sent as recorded', () => {
    const wrapper = mountComponent([
      { ...audioAttachment, sendAsRecordedAudio: true },
    ]);

    const toggle = wrapper.find('[aria-label="Send as audio file"]');
    expect(toggle.attributes('aria-pressed')).toBe('true');
  });

  it('recognizes an MP3 when direct upload returns a generic MIME type', () => {
    const wrapper = mountComponent([
      {
        id: 2,
        resource: {
          filename: 'customer-testimonial.mp3',
          content_type: 'application/octet-stream',
          byte_size: 2048,
        },
      },
    ]);

    expect(wrapper.findComponent(Icon).props('icon')).toBe(
      'i-lucide-audio-lines'
    );
    expect(
      wrapper.find('[aria-label="Send as recorded voice message"]').exists()
    ).toBe(true);
  });

  it('does not show the toggle outside Whatsmeow conversations', () => {
    const wrapper = mountComponent([audioAttachment], false);

    expect(
      wrapper.find('[aria-label="Send as recorded voice message"]').exists()
    ).toBe(false);
  });
});
