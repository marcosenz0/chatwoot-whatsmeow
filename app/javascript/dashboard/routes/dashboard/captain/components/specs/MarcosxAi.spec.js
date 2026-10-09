import { flushPromises, mount, shallowMount } from '@vue/test-utils';
import { vi } from 'vitest';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import AgentEditor from '../AgentEditor.vue';
import AiModelSelect from '../AiModelSelect.vue';
import AiPlayground from '../AiPlayground.vue';
import AiSelect from '../AiSelect.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: { runPlayground: vi.fn() },
}));
const agent = {
  id: 1,
  name: 'Support',
  description: '',
  instructions: 'Be kind',
  inbox_ids: [1],
  config: {
    provider: 'openai',
    model: 'gpt-6.1-sol',
    reasoning_effort: 'medium',
    auto_response_enabled: false,
    split_messages: true,
  },
};
const catalogs = {
  openai: {
    models: [
      {
        id: 'gpt-6.1-sol',
        name: 'gpt-6.1-sol',
        recommended: true,
        vision: true,
        files: true,
        reasoning: true,
      },
      { id: 'gpt-4.1', name: 'gpt-4.1' },
    ],
  },
};
const props = {
  agent,
  agents: [agent, { id: 2, name: 'Other', inbox_ids: [3] }],
  canEdit: true,
  inboxes: [
    { id: 1, name: 'WhatsApp', channel_type: 'Channel::Whatsmeow' },
    { id: 2, name: 'Telegram', channel_type: 'Channel::TelegramPersonal' },
    { id: 3, name: 'Email', channel_type: 'Channel::Email' },
  ],
  catalogs,
  credentials: [{ provider: 'openai', configured: true, enabled: true }],
};

describe('MarcoXIA agent configuration', () => {
  it('offers a searchable app menu and emits the selected model identifier', async () => {
    const wrapper = mount(AiModelSelect, {
      props: { modelValue: 'gpt-6.1-sol', models: catalogs.openai.models },
      global: {
        stubs: {
          DropdownFloating: {
            template: '<div data-dropdown-menu><slot /></div>',
          },
        },
      },
    });
    expect(wrapper.find('select').exists()).toBe(false);
    await wrapper.get('button').trigger('click');
    await wrapper.get('input[type="search"]').setValue('4.1');
    expect(wrapper.findAll('[role="option"]')).toHaveLength(1);
    await wrapper.get('[role="option"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual(['gpt-4.1']);
  });
  it('preserves the selected model when it is absent from the catalog', () => {
    const wrapper = mount(AiModelSelect, {
      props: { modelValue: 'legacy-model', models: catalogs.openai.models },
    });
    expect(wrapper.get('button').text()).toBe('legacy-model');
  });
  it('supports keyboard navigation and returns focus to the selector', async () => {
    const wrapper = mount(AiSelect, {
      attachTo: document.body,
      props: {
        modelValue: 'one',
        label: 'Models',
        options: [
          { value: 'one', label: 'One' },
          { value: 'two', label: 'Two' },
        ],
      },
      global: {
        stubs: {
          DropdownFloating: {
            template: '<div data-dropdown-menu><slot /></div>',
          },
        },
      },
    });
    const trigger = wrapper.get('button');
    await trigger.trigger('keydown', { key: 'ArrowDown' });
    await flushPromises();
    expect(document.activeElement.textContent).toContain('One');
    await wrapper
      .get('[role="option"]')
      .trigger('keydown', { key: 'ArrowDown' });
    expect(document.activeElement.textContent).toContain('Two');
    await wrapper
      .findAll('[role="option"]')[1]
      .trigger('keydown', { key: 'Escape' });
    expect(wrapper.find('[role="listbox"]').exists()).toBe(false);
    expect(document.activeElement).toBe(trigger.element);
    wrapper.unmount();
  });
  it('selects every available inbox without stealing another agent inbox', async () => {
    const wrapper = mount(AgentEditor, { props });
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('MARCOX_AI.ALL_INBOXES'))
      .trigger('click');
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('save')[0][0].inbox_ids).toEqual([1, 2]);
  });
  it('keeps the supplied profile untouched until it is saved', async () => {
    const wrapper = shallowMount(AgentEditor, { props });
    await wrapper.find('input[maxlength="120"]').setValue('Edited support');
    expect(agent.name).toBe('Support');
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('save')[0][0].name).toBe('Edited support');
  });
  it('disables editing for an operator without admin permission', () => {
    const wrapper = shallowMount(AgentEditor, {
      props: { ...props, canEdit: false },
    });
    expect(wrapper.find('fieldset').attributes()).toHaveProperty('disabled');
  });
  it('preserves a different agent model and enabled state when switching profiles', async () => {
    const wrapper = shallowMount(AgentEditor, { props });
    await wrapper.setProps({
      agent: {
        ...agent,
        id: 2,
        name: 'Other',
        config: {
          ...agent.config,
          provider: 'gemini',
          model: 'individual-model',
          auto_response_enabled: true,
        },
      },
    });
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')[0][0].config).toMatchObject({
      provider: 'gemini',
      model: 'individual-model',
      auto_response_enabled: true,
    });
    wrapper.unmount();
  });
  it('changes the provider only from the provider selector and keeps reasoning independent', async () => {
    const wrapper = shallowMount(AgentEditor, {
      props: {
        ...props,
        catalogs: { ...catalogs, groq: { models: [{ id: 'groq-model' }] } },
      },
    });
    const selectors = wrapper.findAllComponents(AiSelect);
    selectors
      .find(item => item.props('label') === 'MARCOX_AI.EDITOR.PROVIDER')
      .vm.$emit('update:modelValue', 'groq');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')[0][0].config).toMatchObject({
      provider: 'groq',
      model: 'groq-model',
      reasoning_effort: 'medium',
    });
    wrapper.unmount();
  });
  it('updates reasoning without changing the provider or model', async () => {
    const wrapper = shallowMount(AgentEditor, { props });
    wrapper
      .findAllComponents(AiSelect)
      .find(item => item.props('label') === 'MARCOX_AI.EDITOR.REASONING')
      .vm.$emit('update:modelValue', 'high');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')[0][0].config).toMatchObject({
      provider: 'openai',
      model: 'gpt-6.1-sol',
      reasoning_effort: 'high',
    });
    wrapper.unmount();
  });
  it('saves a timezone without altering the general switch or supplied profile', async () => {
    const wrapper = shallowMount(AgentEditor, { props });
    wrapper
      .findAllComponents(AiSelect)
      .find(item => item.props('label') === 'MARCOX_AI.EDITOR.TIMEZONE')
      .vm.$emit('update:modelValue', 'America/Araguaina');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')[0][0].config).toMatchObject({
      timezone: 'America/Araguaina',
      auto_response_enabled: false,
      model: 'gpt-6.1-sol',
    });
    expect(agent.config.timezone).toBeUndefined();
    wrapper.unmount();
  });
});

describe('MarcoXIA private test conversation', () => {
  const plan = { messages: ['Hello'], reaction: null, handoff: false };
  beforeEach(() => {
    MarcosxAiAPI.runPlayground.mockResolvedValue({
      data: {
        response: 'Hello',
        plan,
        user_context: 'First question with image details',
      },
    });
  });
  it('sends multi-turn history to the selected saved agent', async () => {
    const wrapper = mount(AiPlayground, { props: { agents: [agent] } });
    await wrapper.find('textarea').setValue('First question');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    await wrapper.find('textarea').setValue('Follow up');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    const [id, body] = MarcosxAiAPI.runPlayground.mock.calls[1];
    expect(id).toBe(1);
    expect(body.getAll('assistant[history][][role]')).toEqual([
      'user',
      'assistant',
    ]);
    expect(body.getAll('assistant[history][][content]')).toEqual([
      'First question with image details',
      'Hello',
    ]);
  });
  it('displays each reply part and a reaction separately', async () => {
    MarcosxAiAPI.runPlayground.mockResolvedValue({
      data: {
        response: 'Hello\nMore',
        plan: { messages: ['Hello', 'More'], reaction: '👍', handoff: false },
      },
    });
    const wrapper = mount(AiPlayground, { props: { agents: [agent] } });
    await wrapper.find('textarea').setValue('Hi');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain('More');
    expect(wrapper.text()).toContain('MARCOX_AI.PLAYGROUND.REACTION');
  });
  it('rejects oversized attachments before invoking the provider', async () => {
    const wrapper = mount(AiPlayground, { props: { agents: [agent] } });
    Object.defineProperty(wrapper.find('input[type="file"]').element, 'files', {
      value: [{ name: 'large.pdf', size: 26 * 1024 * 1024 }],
    });
    await wrapper.find('input[type="file"]').trigger('change');
    expect(wrapper.text()).toContain('MARCOX_AI.PLAYGROUND.FILE_LIMIT');
    expect(MarcosxAiAPI.runPlayground).not.toHaveBeenCalled();
  });
});
