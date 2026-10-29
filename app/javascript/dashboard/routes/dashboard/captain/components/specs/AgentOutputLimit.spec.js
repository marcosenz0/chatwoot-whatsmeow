import { mount } from '@vue/test-utils';
import AgentOutputLimit from '../AgentOutputLimit.vue';

it('shows a Groq-compatible free-tier default and keeps an explicit paid-plan limit across provider changes', async () => {
  const wrapper = mount(AgentOutputLimit, { props: { provider: 'groq' } });
  expect(wrapper.get('input').element.value).toBe('768');
  await wrapper.get('input').setValue('4096');
  expect(wrapper.emitted('update:modelValue')[0]).toEqual([4096]);
  await wrapper.setProps({ modelValue: 4096, provider: 'openai' });
  expect(wrapper.get('input').element.value).toBe('4096');
  wrapper.unmount();
});

it('keeps provider defaults independent when the operator has not set a limit', async () => {
  const wrapper = mount(AgentOutputLimit, { props: { provider: 'openai' } });
  expect(wrapper.get('input').element.value).toBe('8000');
  await wrapper.setProps({ provider: 'gemini' });
  expect(wrapper.get('input').element.value).toBe('8192');
  await wrapper.setProps({ provider: 'groq' });
  expect(wrapper.get('input').element.value).toBe('768');
  wrapper.unmount();
});
