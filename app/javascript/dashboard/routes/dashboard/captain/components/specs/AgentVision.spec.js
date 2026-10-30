import { flushPromises, mount } from '@vue/test-utils';
import AgentEditor from '../AgentEditor.vue';
import AgentVision from '../AgentVision.vue';
import AgentConnection from '../AgentConnection.vue';
import AiSelect from '../AiSelect.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => ({ replace: vi.fn() }),
}));
vi.mock('dashboard/api/marcosxAi', () => ({ default: {} }));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', () => ({
  default: { template: '<slot />' },
}));

const props = {
  canEdit: true,
  agent: {
    id: 1,
    name: 'Support',
    instructions: 'Help',
    inbox_ids: [],
    config: {
      provider: 'groq',
      model: 'openai/gpt-oss-120b',
      process_images: true,
      vision: { provider: 'groq', model: 'qwen/qwen3.8-27b' },
    },
  },
  catalogs: {
    groq: {
      models: [
        {
          id: 'qwen/qwen3.8-27b',
          name: 'Qwen 3.8 27B',
          vision: true,
          reasoning: true,
          max_images: 3,
        },
        {
          id: 'openai/gpt-oss-120b',
          name: 'GPT-OSS 120B',
          vision: false,
          reasoning: true,
        },
      ],
    },
  },
  credentials: [
    {
      provider: 'groq',
      configured: true,
      enabled: true,
      source: 'integration',
      api_base: 'https://api.groq.com/openai/v1',
    },
  ],
};

it('puts voice immediately after identity and exposes independent image reading in identity', () => {
  const wrapper = mount(AgentEditor, { props });
  expect(
    wrapper
      .findAll('[role="tab"]')
      .slice(0, 3)
      .map(tab => tab.text())
  ).toEqual([
    'MARCOX_AI.EDITOR.IDENTITY',
    'MARCOX_AI.VOICE.TITLE',
    'MARCOX_AI.EDITOR.PROMPT',
  ]);
  expect(wrapper.findComponent(AgentVision).exists()).toBe(true);
  expect(wrapper.text()).toContain('PROVIDERS.INTEGRATION_KEY');
  expect(
    wrapper
      .get('button[aria-label="MARCOX_AI.EDITOR.ENABLE"]')
      .attributes('disabled')
  ).toBeUndefined();
  wrapper.unmount();
});

it('keeps Qwen reading images when the chat model is GPT-OSS and saves the complete settings', async () => {
  const wrapper = mount(AgentEditor, { props });
  const vision = wrapper.findComponent(AgentVision);
  await vision.get('input[min="512"]').setValue('1024');
  await vision.get('input[max="6"]').setValue('2');
  await vision.get('textarea').setValue('Read visible amounts carefully.');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0].config).toMatchObject({
    model: 'openai/gpt-oss-120b',
    process_images: true,
    vision: {
      provider: 'groq',
      model: 'qwen/qwen3.8-27b',
      max_dimension: 1024,
      video_frames: 2,
      instructions: 'Read visible amounts carefully.',
    },
  });
  wrapper.unmount();
});

it('only offers vision models for the image selector while the main selector keeps both chat models', () => {
  const wrapper = mount(AgentEditor, { props });
  const selects = wrapper
    .findComponent(AgentVision)
    .findAllComponents(AiSelect);
  expect(selects[1].props('options').map(option => option.value)).toEqual([
    'qwen/qwen3.8-27b',
  ]);
  expect(
    wrapper
      .findAllComponents(AiSelect)
      .some(
        select =>
          select
            .props('options')
            .filter(option =>
              ['qwen/qwen3.8-27b', 'openai/gpt-oss-120b'].includes(option.value)
            ).length === 2
      )
  ).toBe(true);
  wrapper.unmount();
});

it('includes a newly entered connection key when using the top Save changes button', async () => {
  const wrapper = mount(AgentEditor, { props: { ...props, credentials: [] } });
  const connection = wrapper.findComponent(AgentConnection);
  await connection.get('input[type="password"]').setValue('new-test-key');
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][1]).toEqual([
    expect.objectContaining({ provider: 'groq', api_key: 'new-test-key' }),
  ]);
  wrapper.unmount();
});

it('shows a persistent backend save error in the editor', () => {
  const wrapper = mount(AgentEditor, {
    props: { ...props, error: 'Could not save connection' },
  });
  expect(wrapper.get('[role="alert"]').text()).toBe(
    'Could not save connection'
  );
  wrapper.unmount();
});
