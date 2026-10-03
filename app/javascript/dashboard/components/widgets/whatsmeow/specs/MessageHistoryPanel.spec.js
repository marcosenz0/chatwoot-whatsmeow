import { flushPromises, shallowMount } from '@vue/test-utils';
import DeletedAPI from 'dashboard/api/whatsmeowDeletedMessages';
import StarredAPI from 'dashboard/api/whatsmeowStarredMessages';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import MessageHistoryPanel from '../MessageHistoryPanel.vue';

const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
  useRoute: () => ({ params: { accountId: 1 } }),
}));
vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({
    getters: { 'inboxes/getInboxes': [], getCurrentUserID: 1 },
  }),
}));
vi.mock('dashboard/api/whatsmeowDeletedMessages', () => ({
  default: { get: vi.fn() },
}));
vi.mock('dashboard/api/whatsmeowStarredMessages', () => ({
  default: { get: vi.fn(), sync: vi.fn() },
}));

describe('MessageHistoryPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    DeletedAPI.get.mockResolvedValue({
      data: {
        payload: [
          {
            id: 90,
            conversation_id: 59,
            inbox_id: 1,
            chat_name: 'Test group',
            sender_name: 'Test sender',
            message: {
              id: 90,
              message_type: 0,
              status: 'sent',
              created_at: 1791032400,
              content: 'Retained message',
              content_attributes: { deleted: true, whatsmeow_deleted: true },
            },
          },
        ],
        next_cursor: null,
      },
    });
  });

  it('loads deleted messages with their deletion marker without synchronizing stars', async () => {
    const wrapper = shallowMount(MessageHistoryPanel, {
      props: { deleted: true, conversationId: 59 },
    });
    await flushPromises();
    expect(DeletedAPI.get).toHaveBeenCalledWith(
      expect.objectContaining({ conversation_id: 59 }),
      expect.anything()
    );
    expect(StarredAPI.sync).not.toHaveBeenCalled();
    expect(
      wrapper.findComponent({ name: 'Message' }).props('contentAttributes')
    ).toEqual({
      deleted: true,
      whatsmeowDeleted: true,
    });
    expect(
      wrapper.findAll('button-stub[icon="i-lucide-star-off"]')
    ).toHaveLength(0);
    wrapper.unmount();
  });

  it('opens the original conversation and emits its message anchor', async () => {
    const emitSpy = vi.spyOn(emitter, 'emit');
    const wrapper = shallowMount(MessageHistoryPanel, {
      props: { deleted: true },
    });
    await flushPromises();
    await wrapper.find('article').trigger('click');
    expect(push).toHaveBeenCalledWith({
      path: '/app/accounts/1/conversations/59',
      query: { messageId: '90' },
    });
    expect(emitSpy).toHaveBeenCalledWith(BUS_EVENTS.SCROLL_TO_MESSAGE, {
      messageId: 90,
      conversationId: 59,
    });
    wrapper.unmount();
    emitSpy.mockRestore();
  });
});
