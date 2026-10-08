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
  state: {
    assistant_id: 1,
    enabled: true,
    available: true,
    status: 'paused_by_agent',
  },
  assistants: [
    { id: 1, name: 'Felipe', enabled: true, available: true, model: 'model' },
  ],
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
    expect(MarcosxAiAPI.analyzeConversation).toHaveBeenCalledWith(7, 1, null);
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
      data: {
        state: { ...props.state, status: 'active', manual_activation: true },
      },
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
    expect(wrapper.emitted('updated')[0][0].status).toBe('active');
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
  it('allows writing a reviewed reply when the model recommends waiting', async () => {
    MarcosxAiAPI.getConversationAnalysis.mockResolvedValue({
      data: { analysis: { ...ready, plan: { ...ready.plan, messages: [] } } },
    });
    MarcosxAiAPI.sendConversationAnalysis.mockResolvedValue({
      data: { state: props.state },
    });
    const wrapper = mount(ConversationAiPanel, { props, global });
    wrapper.vm.open();
    await flushPromises();
    const sendButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('MARCOX_AI.ANALYSIS.SEND'));
    expect(sendButton.attributes('disabled')).toBeDefined();
    await wrapper.get('textarea').setValue('   ');
    expect(sendButton.attributes('disabled')).toBeDefined();
    await wrapper.get('textarea').setValue('Reviewed follow-up');
    expect(sendButton.attributes('disabled')).toBeUndefined();
    await sendButton.trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.sendConversationAnalysis).toHaveBeenCalledWith(
      7,
      'snapshot',
      ['Reviewed follow-up']
    );
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
      wrapper
        .findAll('button')
        .some(button => button.text().includes('MARCOX_AI.ANALYSIS.SEND'))
    ).toBe(false);
    wrapper.unmount();
  });
  it('selects a recent history window and requires a new preview before sending', async () => {
    MarcosxAiAPI.getConversationAnalysis.mockResolvedValue({
      data: {
        analysis: ready,
        context: { total_messages_count: 200, messages_limit: null },
      },
    });
    MarcosxAiAPI.analyzeConversation.mockResolvedValue({
      data: { analysis: { ...ready, messages_count: 25, messages_limit: 25 } },
    });
    const wrapper = mount(ConversationAiPanel, { props, global });
    wrapper.vm.open();
    await flushPromises();
    const range = wrapper.get('input[type="range"]');
    expect(range.attributes('max')).toBe('200');
    await range.setValue('25');
    const sendButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('MARCOX_AI.ANALYSIS.SEND'));
    expect(sendButton.attributes('disabled')).toBeDefined();
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('MARCOX_AI.ANALYSIS.ANALYZE'))
      .trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.analyzeConversation).toHaveBeenCalledWith(7, 1, 25);
    expect(sendButton.attributes('disabled')).toBeUndefined();
    wrapper.unmount();
  });
  it('allows individual activation and history review while general support is off', async () => {
    const wrapper = mount(ConversationAiPanel, {
      props: {
        ...props,
        state: { ...props.state, enabled: false },
        assistants: [{ ...props.assistants[0], enabled: false }],
      },
      global,
    });
    wrapper.vm.open();
    await flushPromises();
    const resume = wrapper
      .findAll('button')
      .find(button => button.text().includes('MARCOX_AI.CONVERSATION.RESUME'));
    const analyze = wrapper
      .findAll('button')
      .find(button => button.text().includes('MARCOX_AI.ANALYSIS.ANALYZE'));
    expect(resume.attributes('disabled')).toBeUndefined();
    expect(analyze.attributes('disabled')).toBeUndefined();
    MarcosxAiAPI.updateConversationState.mockResolvedValue({
      data: { state: { ...props.state, status: 'active' } },
    });
    await resume.trigger('click');
    await flushPromises();
    expect(MarcosxAiAPI.updateConversationState).toHaveBeenCalledWith(7, {
      action: 'resume',
      reason: 'agent_action',
    });
    wrapper.unmount();
  });
});
