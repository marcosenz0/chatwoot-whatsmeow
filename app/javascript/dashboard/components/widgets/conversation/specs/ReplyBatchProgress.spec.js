import { flushPromises, mount } from '@vue/test-utils';
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
  const wrapper = mount(ReplyBatchProgress);
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
  const wrapper = mount(ReplyBatchProgress);
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
