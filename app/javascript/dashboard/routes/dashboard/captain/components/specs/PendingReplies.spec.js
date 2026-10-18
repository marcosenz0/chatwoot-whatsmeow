import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/marcosxAi';
import { useMarcosxAiBatches } from 'dashboard/composables/useMarcosxAiBatches';
import PendingReplies from '../PendingReplies.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: {
    getPendingReplies: vi.fn(),
    previewPendingReply: vi.fn(),
    createReplyBatch: vi.fn(),
    getReplyBatch: vi.fn(),
    updateReplyBatch: vi.fn(),
  },
}));
const rows = [1, 2].map(id => ({
  id,
  name: `Person ${id}`,
  trigger_message_id: id + 10,
  message: 'A question',
  sent_at: '2026-10-16T12:00:00Z',
}));
const batch = {
  id: 7,
  status: 'ready',
  mode: 'review',
  counts: { ready: 2 },
  items: rows.map(row => ({
    id: row.id,
    name: row.name,
    status: 'ready',
    plan: { messages: [`Answer ${row.id}`] },
    resources: [],
  })),
};
const options = {
  props: { agent: { id: 3 } },
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
          '<section v-if="visible"><h3>{{ title }}</h3><slot /><slot name="footer" /></section>',
      },
    },
  },
};
beforeEach(() => {
  vi.clearAllMocks();
  useMarcosxAiBatches().resetBatches();
  API.getPendingReplies.mockResolvedValue({
    data: { total: 2, conversations: rows, batch: null },
  });
  API.createReplyBatch.mockResolvedValue({
    data: { batch: structuredClone(batch) },
  });
  API.getReplyBatch.mockResolvedValue({
    data: { batch: structuredClone(batch) },
  });
});

it('refreshes the selection after reserving a batch so the same people cannot be selected again', async () => {
  const wrapper = mount(PendingReplies, options);
  await wrapper.find('button').trigger('click');
  await flushPromises();
  await Promise.all(
    wrapper.findAll('input[type="checkbox"]').map(input => input.setValue(true))
  );
  API.createReplyBatch.mockImplementationOnce(async () => {
    API.getPendingReplies.mockResolvedValue({
      data: { total: 0, conversations: [], batch: null },
    });
    return { data: { batch: { ...batch, status: 'running', mode: 'direct' } } };
  });
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('DIRECT'))
    .trigger('click');
  await flushPromises();
  expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(0);
  expect(wrapper.text()).toContain('TOTAL: 0');
  wrapper.unmount();
});

it('reuses the same request identity after an ambiguous network failure', async () => {
  API.createReplyBatch.mockRejectedValueOnce(
    new Error('Connection lost after submit')
  );
  const wrapper = mount(PendingReplies, options);
  await wrapper.find('button').trigger('click');
  await flushPromises();
  await wrapper.findAll('input[type="checkbox"]')[0].setValue(true);
  const direct = () =>
    wrapper.findAll('button').find(button => button.text().includes('DIRECT'));
  await direct().trigger('click');
  await flushPromises();
  const firstId = API.createReplyBatch.mock.calls[0][1].request_id;
  await direct().trigger('click');
  await flushPromises();
  expect(API.createReplyBatch.mock.calls[1][1].request_id).toBe(firstId);
  wrapper.unmount();
});

it('starts with no selection, previews only on demand and reviews all selected without sending', async () => {
  const wrapper = mount(PendingReplies, options);
  await flushPromises();
  await wrapper.find('button').trigger('click');
  await flushPromises();
  expect(
    wrapper
      .findAll('input[type="checkbox"]')
      .every(input => !input.element.checked)
  ).toBe(true);
  await Promise.all(
    wrapper.findAll('input[type="checkbox"]').map(input => input.setValue(true))
  );
  const analyze = wrapper
    .findAll('button')
    .find(button => button.text().includes('ANALYZE'));
  await analyze.trigger('click');
  await flushPromises();
  expect(API.createReplyBatch).toHaveBeenCalledWith(
    3,
    expect.objectContaining({
      mode: 'review',
      selections: rows.map(row => ({
        id: row.id,
        trigger_message_id: row.trigger_message_id,
      })),
    })
  );
  expect(wrapper.text()).toContain('Answer 1');
  expect(wrapper.text()).toContain('Answer 2');
  expect(API.updateReplyBatch).not.toHaveBeenCalled();
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('BACK'))
    .trigger('click');
  expect(wrapper.text()).toContain('PAGE_SELECT');
  expect(wrapper.text()).not.toContain('Answer 1');
  wrapper.unmount();
});

it('removes a specific review only from this batch and confirms the remaining responses', async () => {
  const wrapper = mount(PendingReplies, options);
  await wrapper.find('button').trigger('click');
  await flushPromises();
  await wrapper.findAll('input[type="checkbox"]')[0].setValue(true);
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('ANALYZE'))
    .trigger('click');
  await flushPromises();
  const changed = structuredClone(batch);
  changed.items[0].status = 'discarded';
  changed.counts = { ready: 1, discarded: 1 };
  API.updateReplyBatch.mockResolvedValue({ data: { batch: changed } });
  await wrapper
    .get('button[aria-label="MARCOX_AI.PENDING.REMOVE Person 1"]')
    .trigger('click');
  await flushPromises();
  expect(API.updateReplyBatch).toHaveBeenCalledWith(3, 7, {
    operation: 'discard',
    item_id: 1,
  });
  expect(wrapper.text()).toContain('Answer 2');
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('SEND_REVIEWED'))
    .trigger('click');
  await flushPromises();
  expect(API.updateReplyBatch).toHaveBeenLastCalledWith(3, 7, {
    operation: 'send',
    item_id: undefined,
  });
  wrapper.unmount();
});

it('queues direct mode without opening reviews and prevents repeated submission while running', async () => {
  API.createReplyBatch.mockResolvedValue({
    data: {
      batch: {
        ...batch,
        mode: 'direct',
        status: 'running',
        counts: { pending: 2 },
      },
    },
  });
  const wrapper = mount(PendingReplies, options);
  await wrapper.find('button').trigger('click');
  await flushPromises();
  await Promise.all(
    wrapper.findAll('input[type="checkbox"]').map(input => input.setValue(true))
  );
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('DIRECT'))
    .trigger('click');
  await flushPromises();
  expect(API.createReplyBatch).toHaveBeenCalledWith(
    3,
    expect.objectContaining({ mode: 'direct' })
  );
  expect(wrapper.text()).not.toContain('REVIEWS');
  expect(
    wrapper
      .findAll('button')
      .find(button => button.text().includes('ANALYZE'))
      .attributes('disabled')
  ).toBeDefined();
  wrapper.unmount();
});
