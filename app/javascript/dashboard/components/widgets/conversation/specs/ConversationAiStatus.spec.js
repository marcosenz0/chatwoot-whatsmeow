import { mount } from '@vue/test-utils';
import ConversationAiStatus from '../ConversationAiStatus.vue';

describe('Conversation AI list indicator', () => {
  const state = {
    status: 'active',
    enabled: true,
    available: true,
    assistant_name: 'Felipe',
  };
  it('shows the robot and active label for individual support', () => {
    const wrapper = mount(ConversationAiStatus, {
      props: {
        chat: {
          status: 'open',
          marcosx_ai: { ...state, manual_activation: true },
        },
      },
    });
    expect(wrapper.text()).toContain('MARCOX_AI.CONVERSATION.ON');
    expect(wrapper.find('.i-lucide-bot').exists()).toBe(true);
  });
  it.each([
    { status: 'open', marcosx_ai: { ...state, status: 'paused_by_agent' } },
    { status: 'open', marcosx_ai: { ...state, enabled: false } },
    { status: 'open', marcosx_ai: { ...state, available: false } },
    { status: 'resolved', marcosx_ai: state },
    { status: 'snoozed', marcosx_ai: state },
    { status: 'open' },
  ])('hides the active indicator for an inactive conversation: %j', chat => {
    expect(mount(ConversationAiStatus, { props: { chat } }).text()).toBe('');
  });
});
