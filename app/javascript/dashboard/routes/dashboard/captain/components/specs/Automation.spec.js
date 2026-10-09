import { flushPromises, mount } from '@vue/test-utils';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import NotificationRecipients from '../NotificationRecipients.vue';
import ConversationMemory from '../ConversationMemory.vue';
import AgentAlertList from '../AgentAlertList.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/marcosxAi', () => ({
  default: {
    getMemory: vi.fn(),
    updateMemory: vi.fn(),
    getAlerts: vi.fn(),
    resolveAlert: vi.fn(),
  },
}));

describe('MarcoXIA automation controls', () => {
  it('keeps multiple explicitly entered WhatsApp recipients and a selected sender inbox', async () => {
    const settings = { user_ids: [], whatsapp_numbers: [], inbox_id: 8 };
    const wrapper = mount(NotificationRecipients, {
      props: {
        modelValue: settings,
        users: [{ id: 1, name: 'Owner' }],
        inboxes: [{ id: 8, name: 'WhatsApp' }],
      },
    });
    await wrapper.get('textarea').setValue('+5563999999999\n+5563888888888');
    await wrapper.get('input').setChecked();
    expect(settings.whatsapp_numbers).toEqual([
      '+5563999999999',
      '+5563888888888',
    ]);
    expect(settings.user_ids).toEqual([1]);
    expect(settings.inbox_id).toBe(8);
    wrapper.unmount();
  });

  it('saves memory mode and recent window without activating AI', async () => {
    MarcosxAiAPI.getMemory.mockResolvedValue({
      data: {
        memory: {
          mode: 'summary_recent',
          recent_limit: 20,
          summarized_count: 480,
          summary: 'Old decision',
          links: [],
        },
      },
    });
    MarcosxAiAPI.updateMemory.mockResolvedValue({ data: {} });
    const wrapper = mount(ConversationMemory, {
      props: { conversationId: 92 },
    });
    await flushPromises();
    await wrapper.get('input').setValue(40);
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('SAVE_MEMORY'))
      .trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.updateMemory).toHaveBeenCalledWith(92, {
      mode: 'summary_recent',
      recent_limit: 40,
    });
    expect(wrapper.text()).toContain('Old decision');
    wrapper.unmount();
  });

  it('resolves a pending alert using a distinct action', async () => {
    MarcosxAiAPI.getAlerts.mockResolvedValue({
      data: {
        alerts: [
          {
            id: 1,
            conversation_id: 92,
            contact: 'Owner',
            name: 'Help',
            status: 'open',
            reason: 'Help',
            deliveries: [],
          },
        ],
      },
    });
    MarcosxAiAPI.resolveAlert.mockResolvedValue({ data: {} });
    const wrapper = mount(AgentAlertList, { props: { conversationId: 92 } });
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.resolveAlert).toHaveBeenCalledWith(1);
    expect(wrapper.text()).toContain('RESOLVE_HINT');
    wrapper.unmount();
  });
});
