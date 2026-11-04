import { mount, flushPromises } from '@vue/test-utils';
import AgentThinking from '../AgentThinking.vue';
import AiSelect from '../AiSelect.vue';
import AgentEditor from '../AgentEditor.vue';
import AgentFallback from '../AgentFallback.vue';
import AgentRateLimitRetry from '../AgentRateLimitRetry.vue';
import AiToggleRow from '../AiToggleRow.vue';
import { invertConnections } from '../connectionDefaults';

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => ({ replace: vi.fn() }),
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', () => ({
  default: { template: '<slot />' },
}));

const qwen = {
  id: 'qwen/qwen3.8-27b',
  reasoning: true,
  reasoning_levels: ['none', 'default', 'low', 'medium', 'high'],
  reasoning_default: 'medium',
};
const oss = {
  id: 'openai/gpt-oss-120b',
  reasoning: true,
  reasoning_levels: ['low', 'medium', 'high'],
  reasoning_default: 'medium',
};
const luna = {
  id: 'gpt-6-luna',
  reasoning: true,
  reasoning_levels: ['none', 'low', 'medium', 'high', 'xhigh', 'max'],
  reasoning_default: 'medium',
};

it.each([qwen, oss, luna])('shows only the documented levels of $id', model => {
  const wrapper = mount(AgentThinking, {
    props: { model, modelValue: 'medium' },
  });
  expect(
    wrapper
      .findComponent(AiSelect)
      .props('options')
      .map(item => item.value)
  ).toEqual(model.reasoning_levels);
  wrapper
    .findComponent(AiSelect)
    .vm.$emit('update:modelValue', model.reasoning_levels[0]);
  expect(wrapper.emitted('update:modelValue')[0]).toEqual([
    model.reasoning_levels[0],
  ]);
  wrapper.unmount();
});

it('distinguishes a non-thinking model from an unavailable catalog without changing an in-progress choice', async () => {
  const wrapper = mount(AgentThinking, { props: { modelValue: 'none' } });
  expect(wrapper.text()).toContain('THINKING.UNKNOWN');
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  await wrapper.setProps({
    model: { id: 'llama', reasoning: false, reasoning_levels: [] },
  });
  expect(wrapper.text()).toContain('THINKING.UNSUPPORTED');
  expect(wrapper.findComponent(AiSelect).exists()).toBe(false);
  wrapper.unmount();
});

it('normalizes none when switching to GPT-OSS and keeps none when switching between Qwen and Luna', async () => {
  const wrapper = mount(AgentThinking, {
    props: { model: qwen, modelValue: 'none' },
  });
  await wrapper.setProps({ model: luna });
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  await wrapper.setProps({ model: oss });
  expect(wrapper.emitted('update:modelValue')[0]).toEqual(['medium']);
  expect(wrapper.text()).toContain('THINKING.REQUIRED');
  wrapper.unmount();
});

it('keeps the control read-only without hiding the selected level', () => {
  const wrapper = mount(AgentThinking, {
    props: { model: luna, modelValue: 'none', disabled: true },
  });
  expect(wrapper.findComponent(AiSelect).props()).toMatchObject({
    modelValue: 'none',
    disabled: true,
  });
  wrapper.unmount();
});

it('places thinking immediately after provider and model in both primary and reserve and saves their own choices', async () => {
  const wrapper = mount(AgentEditor, {
    props: {
      agent: {
        id: 1,
        name: 'QA',
        instructions: 'Neutral',
        inbox_ids: [],
        config: {
          provider: 'groq',
          model: qwen.id,
          reasoning_effort: 'medium',
          fallback: {
            enabled: true,
            provider: 'openai',
            model: luna.id,
            reasoning_effort: 'high',
          },
        },
      },
      canEdit: true,
      catalogs: { groq: { models: [qwen, oss] }, openai: { models: [luna] } },
    },
  });
  const thoughts = wrapper.findAllComponents(AgentThinking).slice(0, 2);
  expect(thoughts).toHaveLength(2);
  for (const control of thoughts) {
    expect(control.element.previousElementSibling.className).toContain('grid');
    expect(
      control.element.previousElementSibling.querySelectorAll(
        'button[aria-haspopup]'
      )
    ).toHaveLength(2);
  }
  thoughts[0].findComponent(AiSelect).vm.$emit('update:modelValue', 'none');
  thoughts[1].findComponent(AiSelect).vm.$emit('update:modelValue', 'low');
  const retry = wrapper.findAllComponents(AgentRateLimitRetry)[0];
  retry.findComponent(AiToggleRow).vm.$emit('update:modelValue', false);
  await flushPromises();
  wrapper.find('form').trigger('submit');
  await flushPromises();
  const saved = wrapper.emitted('save').at(-1)[0].config;
  expect(saved.reasoning_effort).toBe('none');
  expect(saved.fallback.reasoning_effort).toBe('low');
  expect(saved.retry_rate_limits).toBe(false);
  expect(saved.fallback.retry_rate_limits).toBe(true);
  wrapper.unmount();
});

it('swaps each model together with its thought level and retry policy, preserving return behavior', () => {
  const main = {
    provider: 'groq',
    model: qwen.id,
    reasoning_effort: 'none',
    retry_rate_limits: true,
  };
  const reserve = {
    provider: 'openai',
    model: luna.id,
    reasoning_effort: 'high',
    retry_rate_limits: false,
    retry_primary: false,
    enabled: true,
  };
  invertConnections(main, reserve);
  expect(main).toMatchObject({
    provider: 'openai',
    reasoning_effort: 'high',
    retry_rate_limits: false,
  });
  expect(reserve).toMatchObject({
    provider: 'groq',
    reasoning_effort: 'none',
    retry_rate_limits: true,
    retry_primary: false,
    enabled: true,
  });
});

it('exposes thinking in the reserve without depending on the primary model capabilities', () => {
  const wrapper = mount(AgentFallback, {
    props: {
      modelValue: {
        enabled: true,
        provider: 'openai',
        model: luna.id,
        reasoning_effort: 'none',
      },
      catalogs: { openai: { models: [luna] } },
    },
  });
  expect(
    wrapper
      .findComponent(AgentThinking)
      .findComponent(AiSelect)
      .props('modelValue')
  ).toBe('none');
  wrapper.unmount();
});
