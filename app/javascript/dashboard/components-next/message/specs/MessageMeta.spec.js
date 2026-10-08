import { mount } from '@vue/test-utils';
import { computed, nextTick, ref } from 'vue';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import MessageMeta from '../MessageMeta.vue';

const state = vi.hoisted(() => ({ channelType: '', context: {} }));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key =>
    computed(() => {
      if (key === 'getSelectedChat') return { inbox_id: 7 };
      if (key === 'inboxes/getInboxById') {
        return () => ({ id: 7, channel_type: state.channelType });
      }
      return null;
    }),
}));
vi.mock('../provider.js', () => ({
  useMessageContext: () => state.context,
}));
vi.mock('shared/composables/useExactTimestamp', () => ({
  useExactTimestamp: () => () => 'Test timestamp',
}));

describe('Telegram personal message status', () => {
  beforeEach(() => {
    state.channelType = 'Channel::TelegramPersonal';
    state.context = {
      status: ref('sent'),
      sourceId: ref('telegram:123:77'),
      isPrivate: ref(false),
      createdAt: ref(1720000000),
      messageType: ref(1),
      contentAttributes: ref({}),
    };
  });

  const render = () =>
    mount(MessageMeta, {
      global: {
        stubs: { Icon: true, MessageStatus: true },
      },
    });

  it('changes the sent indicator to read when the account receives a read receipt', async () => {
    const wrapper = render();
    expect(
      wrapper.findComponent({ name: 'MessageStatus' }).props('status')
    ).toBe('sent');
    state.context.status.value = 'read';
    await nextTick();
    expect(
      wrapper.findComponent({ name: 'MessageStatus' }).props('status')
    ).toBe('read');
  });

  it('keeps an unacknowledged outgoing message in progress', () => {
    state.context.sourceId.value = null;
    const wrapper = render();
    expect(
      wrapper.findComponent({ name: 'MessageStatus' }).props('status')
    ).toBe('progress');
  });

  it('does not show delivery status for private notes', () => {
    state.context.isPrivate.value = true;
    expect(render().findComponent({ name: 'MessageStatus' }).exists()).toBe(
      false
    );
  });

  it('preserves the sent indicator for Telegram bot messages', () => {
    state.channelType = 'Channel::Telegram';
    const wrapper = render();
    expect(
      wrapper.findComponent({ name: 'MessageStatus' }).props('status')
    ).toBe('sent');
  });

  it('preserves the read indicator for Whatsmeow', () => {
    state.channelType = 'Channel::Whatsmeow';
    state.context.status.value = 'read';
    const wrapper = render();
    expect(
      wrapper.findComponent({ name: 'MessageStatus' }).props('status')
    ).toBe('read');
  });
  it('shows an AI signature beside the timestamp and delivery status', () => {
    state.context.isMarcoxMessage = ref(true);
    state.context.sender = ref({ name: 'Felipe' });
    const wrapper = render();
    expect(wrapper.get('[aria-label="MARCOX_AI.CONVERSATION.SIGNATURE"]').exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'MessageStatus' }).exists()).toBe(true);
    expect(wrapper.findAllComponents({ name: 'Icon' }).some(icon => icon.props('icon') === 'i-lucide-bot')).toBe(true);
  });
});
