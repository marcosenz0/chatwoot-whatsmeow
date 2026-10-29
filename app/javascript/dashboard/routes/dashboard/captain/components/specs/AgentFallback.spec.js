import { mount, flushPromises } from '@vue/test-utils';
import AgentFallback from '../AgentFallback.vue';
import AgentConnection from '../AgentConnection.vue';
import AgentConnectionPicker from '../AgentConnectionPicker.vue';
import AiSelect from '../AiSelect.vue';
import API from 'dashboard/api/marcosxAi';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: { saveCredential: vi.fn() },
}));

const main = {
  id: 1,
  name: 'Main account',
  provider: 'groq',
  configured: true,
  enabled: true,
  api_base: 'https://api.groq.com/openai/v1',
  health: {},
};
const reserve = { ...main, id: 2, name: 'Reserve account' };
const fallback = {
  enabled: true,
  provider: 'groq',
  model: 'qwen/qwen3.8-27b',
  connection_id: 2,
};
const catalogs = {
  groq: {
    models: [
      { id: 'qwen/qwen3.8-27b', name: 'Qwen', vision: true },
      { id: 'openai/gpt-oss-120b', name: 'GPT-OSS', vision: false },
    ],
  },
};

it('selects distinct same-provider accounts and tests the chosen reserve model and connection', async () => {
  const wrapper = mount(AgentFallback, {
    props: {
      modelValue: { ...fallback },
      credentials: [main, reserve],
      catalogs,
      canEdit: true,
    },
  });
  expect(wrapper.findComponent(AgentConnection).props('credential').id).toBe(2);
  const picker = wrapper
    .findComponent(AgentConnectionPicker)
    .findComponent(AiSelect);
  expect(picker.props('options').map(option => option.value)).toEqual([
    '',
    '1',
    '2',
  ]);
  wrapper.findComponent(AgentConnection).vm.$emit('test');
  await flushPromises();
  expect(wrapper.emitted('testConnection')[0]).toEqual([
    'groq',
    2,
    'qwen/qwen3.8-27b',
  ]);
  wrapper.unmount();
});

it('shows the failed connection and the active reserve while retaining an in-progress key edit on a health refresh', async () => {
  const wrapper = mount(AgentConnection, {
    props: {
      provider: 'groq',
      credential: {
        ...main,
        health: { state: 'error', error: 'Quota reached' },
      },
      canEdit: true,
    },
  });
  expect(wrapper.text()).toContain('Quota reached');
  expect(wrapper.find('.i-lucide-circle-x').exists()).toBe(true);
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('EDIT_KEY'))
    .trigger('click');
  await wrapper.get('input[type="password"]').setValue('replacement-test-key');
  await wrapper.setProps({
    credential: { ...main, health: { state: 'healthy' } },
    active: true,
  });
  expect(wrapper.get('input[type="password"]').element.value).toBe(
    'replacement-test-key'
  );
  expect(wrapper.text()).toContain('MARCOX_AI.FALLBACK.IN_USE');
  wrapper.unmount();
});

it('adds a separately named Groq account and selects its returned ID without exposing the key', async () => {
  API.saveCredential.mockResolvedValue({ data: { credential: reserve } });
  const wrapper = mount(AgentConnectionPicker, {
    props: {
      provider: 'groq',
      credentials: [main],
      defaults: { default_model: 'qwen/qwen3.8-27b' },
    },
  });
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('ADD_CONNECTION'))
    .trigger('click');
  await wrapper.get('input[type="text"]').setValue('Reserve account');
  await wrapper.get('input[type="password"]').setValue('new-private-test-key');
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('PROVIDERS.CONNECT'))
    .trigger('click');
  await flushPromises();
  expect(API.saveCredential).toHaveBeenCalledWith(null, {
    credential: expect.objectContaining({
      provider: 'groq',
      name: 'Reserve account',
      api_key: 'new-private-test-key',
    }),
  });
  expect(wrapper.emitted('update:modelValue')[0]).toEqual([2]);
  expect(wrapper.emitted('connectionCreated')[0]).toEqual([reserve]);
  expect(wrapper.find('input[type="password"]').exists()).toBe(false);
  expect(wrapper.text()).not.toContain('new-private-test-key');
  wrapper.unmount();
});

it('keeps a failed account creation visible for correction', async () => {
  API.saveCredential.mockRejectedValue({
    response: { data: { error: 'Choose another account name' } },
  });
  const wrapper = mount(AgentConnectionPicker, { props: { provider: 'groq' } });
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('ADD_CONNECTION'))
    .trigger('click');
  await wrapper.get('input[type="text"]').setValue('Main account');
  await wrapper.get('input[type="password"]').setValue('private-test-key');
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('PROVIDERS.CONNECT'))
    .trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe(
    'Choose another account name'
  );
  expect(wrapper.emitted('connectionCreated')).toBeUndefined();
  wrapper.unmount();
});

it('uses a transcription model when changing the reserve audio provider', async () => {
  const settings = { ...fallback };
  const wrapper = mount(AgentFallback, {
    props: {
      modelValue: settings,
      feature: 'transcription',
      canEdit: true,
      catalogs: { openai: { models: [{ id: 'gpt-4o-transcribe' }] } },
    },
  });
  wrapper.findComponent(AiSelect).vm.$emit('update:modelValue', 'openai');
  await flushPromises();
  expect(settings).toMatchObject({
    provider: 'openai',
    model: 'gpt-4o-transcribe',
    connection_id: null,
  });
  wrapper.unmount();
});

it('filters out text-only models for the visual reserve and hides its fields when disabled', async () => {
  const settings = { ...fallback };
  const wrapper = mount(AgentFallback, {
    props: { modelValue: settings, catalogs, vision: true, canEdit: true },
  });
  expect(
    wrapper
      .findAllComponents(AiSelect)[1]
      .props('options')
      .map(option => option.value)
  ).toEqual(['qwen/qwen3.8-27b']);
  await wrapper.setProps({ modelValue: { ...settings, enabled: false } });
  expect(wrapper.findComponent(AgentConnection).exists()).toBe(false);
  wrapper.unmount();
});
