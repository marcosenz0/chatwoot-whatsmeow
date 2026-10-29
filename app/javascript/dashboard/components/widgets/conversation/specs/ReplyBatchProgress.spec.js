import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import API from 'dashboard/api/marcosxAi';
import { useMarcosxAiBatches } from 'dashboard/composables/useMarcosxAiBatches';
import ReplyBatchProgress from '../ReplyBatchProgress.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: {
    getActiveReplyBatches: vi.fn(),
    getReplyBatch: vi.fn(),
    updateReplyBatch: vi.fn(),
  },
}));
const record = {
  id: 7,
  assistant_id: 3,
  assistant_name: 'Support',
  status: 'running',
  counts: { sending: 1 },
  items: [{ id: 1, name: 'Person 1', status: 'sending' }],
};
const options = {
  global: {
    stubs: {
      Avatar: true,
      AudioPlayer: true,
      Dialog: {
        props: ['title'],
        setup(_, { expose }) {
          const visible = ref(false);
          expose({
            open: () => {
              visible.value = true;
            },
            close: () => {
              visible.value = false;
            },
          });
          return { visible };
        },
        template:
          '<section v-if="visible" role="dialog"><h3>{{ title }}</h3><slot /><slot name="footer" /></section>',
      },
    },
  },
};
const readyBatch = {
  ...record,
  account_id: 1,
  status: 'ready',
  counts: { ready: 2 },
  items: [1, 2].map(id => ({
    id,
    conversation_id: id + 10,
    name: `Person ${id}`,
    status: 'ready',
    plan: { messages: [`Prepared answer ${id}`] },
    resources: [],
  })),
};
beforeEach(() => {
  vi.useFakeTimers();
  vi.clearAllMocks();
  useMarcosxAiBatches().resetBatches();
  API.getActiveReplyBatches.mockResolvedValue({
    data: { batches: [structuredClone(record)] },
  });
  API.getReplyBatch.mockResolvedValue({
    data: { batch: structuredClone(record) },
  });
});
afterEach(() => vi.useRealTimers());

it('restores a running batch and keeps tracking after minimizing, with names and failures visible', async () => {
  const wrapper = mount(ReplyBatchProgress, options);
  await flushPromises();
  expect(wrapper.text()).toContain('Person 1');
  await wrapper
    .get('button[aria-label="MARCOX_AI.PENDING.MINIMIZE"]')
    .trigger('click');
  API.getReplyBatch.mockResolvedValue({
    data: {
      batch: {
        ...record,
        status: 'completed',
        counts: { sent: 1 },
        items: [
          {
            id: 1,
            name: 'Person 1',
            status: 'sent',
            delivery_status: 'delivery_failed',
          },
        ],
      },
    },
  });
  await vi.advanceTimersByTimeAsync(2000);
  await flushPromises();
  expect(API.getReplyBatch).toHaveBeenCalledTimes(2);
  await wrapper.get('button').trigger('click');
  expect(wrapper.text()).toContain('Person 1');
  expect(wrapper.text()).toContain('STATUS.delivery_failed');
  wrapper.unmount();
});

it('does not claim success when progress polling disconnects and supports stopping the actual batch', async () => {
  API.getReplyBatch.mockRejectedValue(new Error('offline'));
  const wrapper = mount(ReplyBatchProgress, options);
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toContain('CONNECTION_ERROR');
  API.updateReplyBatch.mockResolvedValue({
    data: { batch: { ...record, status: 'cancelled' } },
  });
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('STOP'))
    .trigger('click');
  await flushPromises();
  expect(API.updateReplyBatch).toHaveBeenCalledWith(3, 7, {
    operation: 'cancel',
  });
  expect(wrapper.text()).toContain('STATUS.cancelled');
  wrapper.unmount();
});

it('opens the actual generated responses from a recovered ready batch and reviews a clicked person first', async () => {
  API.getActiveReplyBatches.mockResolvedValue({
    data: { batches: [readyBatch] },
  });
  API.getReplyBatch.mockResolvedValue({ data: { batch: readyBatch } });
  const wrapper = mount(ReplyBatchProgress, options);
  await flushPromises();
  expect(wrapper.get('progress').attributes('aria-label')).toContain(
    'PREPARED'
  );
  await wrapper
    .get('button[aria-label="MARCOX_AI.PENDING.REVIEW_CONTACT Person 2"]')
    .trigger('click');
  await flushPromises();
  const dialog = wrapper.get('[role="dialog"]');
  expect(dialog.findAll('article')[0].text()).toContain('Prepared answer 2');
  expect(dialog.text()).toContain('Prepared answer 1');
  expect(dialog.get('a').attributes('href')).toBe(
    '/app/accounts/1/conversations/12'
  );
  expect(API.updateReplyBatch).not.toHaveBeenCalled();
  API.updateReplyBatch.mockResolvedValue({
    data: { batch: { ...readyBatch, status: 'running' } },
  });
  await dialog
    .findAll('button')
    .find(button => button.text().includes('SEND_REVIEWED'))
    .trigger('click');
  await flushPromises();
  expect(API.updateReplyBatch).toHaveBeenCalledWith(3, 7, {
    operation: 'send',
    item_id: undefined,
  });
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  expect(wrapper.get('aside').text()).toContain('STATUS.running');
  wrapper.unmount();
});

it('sends a prepared batch directly from the monitor without requiring the review dialog', async () => {
  API.getActiveReplyBatches.mockResolvedValue({
    data: { batches: [readyBatch] },
  });
  API.getReplyBatch.mockResolvedValue({ data: { batch: readyBatch } });
  API.updateReplyBatch.mockResolvedValue({
    data: { batch: { ...readyBatch, status: 'running' } },
  });
  const wrapper = mount(ReplyBatchProgress, options);
  await flushPromises();
  const send = wrapper
    .findAll('button')
    .find(button => button.text().includes('SEND_ALL'));
  expect(send.attributes('disabled')).toBeUndefined();
  await send.trigger('click');
  await send.trigger('click');
  await flushPromises();
  expect(API.updateReplyBatch).toHaveBeenCalledTimes(1);
  expect(API.updateReplyBatch).toHaveBeenCalledWith(3, 7, {
    operation: 'send',
  });
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  wrapper.unmount();
});

it('closes a ready monitor without cancelling it or reopening it on discovery; explicit review can reveal it again', async () => {
  API.getActiveReplyBatches.mockResolvedValue({
    data: { batches: [readyBatch] },
  });
  API.getReplyBatch.mockResolvedValue({ data: { batch: readyBatch } });
  const wrapper = mount(ReplyBatchProgress, options);
  await flushPromises();
  await wrapper
    .get('button[aria-label="MARCOX_AI.PENDING.CLOSE_MONITOR"]')
    .trigger('click');
  expect(wrapper.find('aside').exists()).toBe(false);
  await vi.advanceTimersByTimeAsync(16000);
  await flushPromises();
  expect(API.getActiveReplyBatches).toHaveBeenCalledTimes(2);
  expect(wrapper.find('aside').exists()).toBe(false);
  expect(API.updateReplyBatch).not.toHaveBeenCalled();
  useMarcosxAiBatches().revealBatch(7);
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('REVIEWS'))
    .trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="dialog"]').text()).toContain('Prepared answer 1');
  wrapper.unmount();
});

it('keeps a send failure actionable without declaring success or automatically resubmitting', async () => {
  API.getActiveReplyBatches.mockResolvedValue({
    data: { batches: [readyBatch] },
  });
  API.getReplyBatch.mockResolvedValue({ data: { batch: readyBatch } });
  API.updateReplyBatch.mockRejectedValue(new Error('connection interrupted'));
  const wrapper = mount(ReplyBatchProgress, options);
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('SEND_ALL'))
    .trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toContain('ACTION_ERROR');
  await vi.advanceTimersByTimeAsync(2000);
  expect(API.updateReplyBatch).toHaveBeenCalledTimes(1);
  expect(wrapper.text()).toContain('STATUS.ready');
  wrapper.unmount();
});

it('does not show a completed historical batch adopted by Pending while idle', async () => {
  API.getActiveReplyBatches.mockResolvedValue({ data: { batches: [] } });
  useMarcosxAiBatches().rememberBatch({
    ...record,
    status: 'completed',
    items: [{ id: 1, status: 'sent', delivery_status: 'delivered' }],
  });
  const wrapper = mount(ReplyBatchProgress, options);
  await flushPromises();
  expect(wrapper.find('aside').exists()).toBe(false);
  wrapper.unmount();
});

it('automatically hides a newly completed batch and does not rediscover its old result', async () => {
  const wrapper = mount(ReplyBatchProgress, options);
  await flushPromises();
  API.getReplyBatch.mockResolvedValue({
    data: {
      batch: {
        ...record,
        status: 'completed',
        items: [
          {
            id: 1,
            name: 'Person 1',
            status: 'sent',
            delivery_status: 'delivered',
          },
        ],
      },
    },
  });
  await vi.advanceTimersByTimeAsync(2000);
  expect(wrapper.text()).toContain('STATUS.completed');
  await vi.advanceTimersByTimeAsync(8000);
  expect(wrapper.find('aside').exists()).toBe(false);
  wrapper.unmount();
});

it('shows activation work only while the request is pending and includes the contact avatar in results', async () => {
  API.getActiveReplyBatches.mockResolvedValue({ data: { batches: [] } });
  const state = useMarcosxAiBatches();
  const wrapper = mount(ReplyBatchProgress, options);
  await flushPromises();
  state.beginOperation('toggle-1', 'Support', 'Enabling general support');
  await flushPromises();
  expect(wrapper.get('[role="status"]').text()).toContain(
    'Enabling general support'
  );
  state.finishOperation('toggle-1');
  await flushPromises();
  expect(wrapper.find('aside').exists()).toBe(false);
  state.rememberBatch({
    ...record,
    items: [
      {
        id: 1,
        name: 'Person 1',
        status: 'sending',
        avatar_url: 'https://example.com/person.png',
      },
    ],
  });
  await flushPromises();
  expect(wrapper.get('avatar-stub').attributes('src')).toBe(
    'https://example.com/person.png'
  );
  wrapper.unmount();
});
