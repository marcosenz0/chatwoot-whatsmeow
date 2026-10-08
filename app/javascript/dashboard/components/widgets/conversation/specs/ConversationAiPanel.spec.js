import { flushPromises, mount } from '@vue/test-utils';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import ConversationAiPanel from '../ConversationAiPanel.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: {
    getConversationAnalysis: vi.fn(),
    analyzeConversation: vi.fn(),
    sendConversationAnalysis: vi.fn(),
    getConversationState: vi.fn(),
    updateConversationState: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const props = {
  chat: { id: 7, status: 'open' },
  state: { assistant_id: 1, enabled: true, status: 'paused_by_agent' },
  assistants: [{ id: 1, name: 'Felipe', enabled: true, model: 'model' }],
};
const ready = {
  id: 'snapshot',
  status: 'ready',
  messages_count: 200,
  summary: 'Customer prefers short replies',
  next_step: 'Acknowledge the preference',
  plan: { messages: ['I understand'], reaction: null, handoff: false },
};
const global = {
  stubs: {
    Dialog: {
      setup(_, { expose }) {
        expose({ open() {}, close() {} });
      },
      template: '<div><slot /><slot name="footer" /></div>',
    },
  },
};

describe('Conversation history review', () => {
  beforeEach(() => {
    MarcosxAiAPI.getConversationAnalysis.mockResolvedValue({
      data: { analysis: { status: 'idle' } },
    });
    MarcosxAiAPI.getConversationState.mockResolvedValue({
      data: { state: props.state },
    });
  });
  it('does not send a reply when analyzing or opening the history preview', async () => {
    MarcosxAiAPI.analyzeConversation.mockResolvedValue({
      data: { analysis: ready },
    });
    const wrapper = mount(ConversationAiPanel, { props, global });
    wrapper.vm.open();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('MARCOX_AI.ANALYSIS.ANALYZE'))
      .trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.analyzeConversation).toHaveBeenCalledWith(7, 1);
    expect(MarcosxAiAPI.sendConversationAnalysis).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(ready.summary);
    expect(wrapper.text()).toContain(ready.next_step);
    wrapper.unmount();
  });
  it('sends only after review and uses the edited reply for the current snapshot', async () => {
    MarcosxAiAPI.getConversationAnalysis.mockResolvedValue({
      data: { analysis: ready },
    });
    MarcosxAiAPI.sendConversationAnalysis.mockResolvedValue({
      data: { state: props.state },
    });
    const wrapper = mount(ConversationAiPanel, { props, global });
    wrapper.vm.open();
    await flushPromises();
    await wrapper.get('textarea').setValue('Edited reply');
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('MARCOX_AI.ANALYSIS.SEND'))
      .trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.sendConversationAnalysis).toHaveBeenCalledWith(
      7,
      'snapshot',
      ['Edited reply']
    );
    expect(wrapper.emitted('updated')[0][0].status).toBe('paused_by_agent');
    expect(wrapper.find('textarea').exists()).toBe(false);
    wrapper.unmount();
  });
  it('ignores a late report from a different conversation', async () => {
    let finish;
    MarcosxAiAPI.getConversationAnalysis.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount(ConversationAiPanel, { props, global });
    wrapper.vm.open();
    await wrapper.setProps({ chat: { id: 8, status: 'open' } });
    finish({ data: { analysis: ready } });
    await flushPromises();
    expect(wrapper.text()).not.toContain(ready.summary);
    expect(MarcosxAiAPI.sendConversationAnalysis).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('requires a fresh analysis when the conversation has changed', async () => {
    MarcosxAiAPI.getConversationAnalysis.mockResolvedValue({
      data: { analysis: { ...ready, status: 'outdated' } },
    });
    const wrapper = mount(ConversationAiPanel, { props, global });
    wrapper.vm.open();
    await flushPromises();
    expect(wrapper.text()).toContain('MARCOX_AI.ANALYSIS.OUTDATED');
    expect(
      wrapper.find('button[aria-label="MARCOX_AI.ANALYSIS.SEND"]').exists()
    ).toBe(false);
    wrapper.unmount();
  });
});
