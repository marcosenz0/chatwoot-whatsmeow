import { mount } from '@vue/test-utils';
import AgentPromptCache from '../AgentPromptCache.vue';
import AiToggleRow from '../AiToggleRow.vue';
import AiSelect from '../AiSelect.vue';

describe('agent prompt cache settings', () => {
  const props = {
    provider: 'openai',
    model: 'gpt-6-luna',
    modelValue: { enabled: true, ttl: '30m' },
  };

  it('preserves the selected lifetime when disabling and lets operators choose longer retention', async () => {
    const wrapper = mount(AgentPromptCache, { props });
    wrapper.getComponent(AiSelect).vm.$emit('update:modelValue', '12h');
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
      enabled: true,
      ttl: '12h',
    });
    await wrapper.setProps({ modelValue: { enabled: true, ttl: '12h' } });
    expect(wrapper.text()).toContain('LONG_HINT');
    wrapper.getComponent(AiToggleRow).vm.$emit('update:modelValue', false);
    expect(wrapper.emitted('update:modelValue')[1][0]).toEqual({
      enabled: false,
      ttl: '12h',
    });
    wrapper.unmount();
  });

  it.each([
    ['groq', 'openai/gpt-oss-120b'],
    ['openai', 'gpt-5.5'],
    ['gemini', 'gemini-2.5-flash'],
  ])('keeps unsupported %s models unchanged', (provider, model) => {
    const wrapper = mount(AgentPromptCache, {
      props: { ...props, provider, model },
    });
    expect(wrapper.getComponent(AiToggleRow).props('disabled')).toBe(true);
    expect(wrapper.findComponent(AiSelect).exists()).toBe(false);
    expect(wrapper.text()).toContain('UNSUPPORTED');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });
});
