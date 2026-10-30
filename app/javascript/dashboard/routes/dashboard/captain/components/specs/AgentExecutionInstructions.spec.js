import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/marcosxAi';
import AgentExecutionInstructions from '../AgentExecutionInstructions.vue';
import AiSelect from '../AiSelect.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: { getEffectivePrompt: vi.fn() },
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', () => ({
  default: { template: '<slot />' },
}));

describe('Execution instruction presets', () => {
  it('loads defaults for the newly selected agent instead of reusing another agent rules', async () => {
    const wrapper = mount(AgentExecutionInstructions, {
      props: {
        assistant: { id: 1, config: {} },
        canEdit: true,
        modelValue: { platform: null, current_request: null, memory: null },
        presets: [],
        presetId: 'system',
      },
    });
    await flushPromises();
    API.getEffectivePrompt.mockResolvedValue({
      data: {
        rules_defaults: {
          platform: 'Second agent rules',
          current_request: 'Second focus',
          memory: 'Second memory',
        },
        placeholders: [],
      },
    });
    await wrapper.setProps({ assistant: { id: 2, config: {} } });
    await flushPromises();
    expect(wrapper.get('#ai-platform-prompt').element.value).toBe(
      'Second agent rules'
    );
    expect(API.getEffectivePrompt).toHaveBeenLastCalledWith(
      2,
      expect.objectContaining({ id: 2 })
    );
    wrapper.unmount();
  });

  beforeEach(() => {
    API.getEffectivePrompt.mockResolvedValue({
      data: {
        rules_defaults: {
          platform: 'Original {{resource_catalog}}',
          current_request: 'Original focus',
          memory: 'Original summary',
        },
        placeholders: ['resource_catalog'],
      },
    });
  });

  it('creates two named versions, switches their actual text and restores the system without deleting either version', async () => {
    const wrapper = mount(AgentExecutionInstructions, {
      props: {
        assistant: { id: 1, config: {} },
        canEdit: true,
        modelValue: { platform: null, current_request: null, memory: null },
        presets: [],
        presetId: 'system',
        'onUpdate:modelValue': value => wrapper.setProps({ modelValue: value }),
        'onUpdate:presets': value => wrapper.setProps({ presets: value }),
        'onUpdate:presetId': value => wrapper.setProps({ presetId: value }),
      },
    });
    await flushPromises();
    expect(wrapper.get('#ai-platform-prompt').element.value).toBe(
      'Original {{resource_catalog}}'
    );
    await wrapper.get('#ai-platform-prompt').setValue('First custom rule');
    await wrapper.get('#ai-memory-prompt').setValue('Short memory');
    await wrapper.get('input').setValue('Preset 1');
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('PROMPT_RULES.ADD'))
      .trigger('click');
    await flushPromises();
    const first = wrapper.props('presets')[0];
    expect(first).toEqual(
      expect.objectContaining({
        name: 'Preset 1',
        rules: {
          platform: 'First custom rule',
          current_request: 'Original focus',
          memory: 'Short memory',
        },
      })
    );
    await wrapper.get('#ai-platform-prompt').setValue('Second custom rule');
    await wrapper.get('input').setValue('Preset 2');
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('PROMPT_RULES.ADD'))
      .trigger('click');
    await flushPromises();
    wrapper.findComponent(AiSelect).vm.$emit('update:modelValue', first.id);
    await flushPromises();
    expect(wrapper.get('#ai-platform-prompt').element.value).toBe(
      'First custom rule'
    );
    expect(wrapper.get('#ai-memory-prompt').element.value).toBe('Short memory');
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('PROMPT_RULES.RESTORE'))
      .trigger('click');
    await flushPromises();
    expect(wrapper.props('presetId')).toBe('system');
    expect(wrapper.props('modelValue')).toEqual({
      platform: null,
      current_request: null,
      memory: null,
    });
    expect(wrapper.get('#ai-platform-prompt').element.value).toBe(
      'Original {{resource_catalog}}'
    );
    expect(wrapper.props('presets')).toHaveLength(2);
    wrapper.unmount();
  });

  it('loads system defaults independently of broken custom text so restore remains possible', async () => {
    const wrapper = mount(AgentExecutionInstructions, {
      props: {
        assistant: {
          id: 1,
          config: {
            prompt_rules: { platform: '{{unknown}}' },
            prompt_preset_id: 'bad',
            prompt_presets: [{ id: 'bad' }],
          },
        },
        canEdit: true,
        modelValue: { platform: '{{unknown}}' },
        presets: [],
        presetId: 'custom',
      },
    });
    await flushPromises();
    expect(API.getEffectivePrompt).toHaveBeenCalledWith(
      1,
      expect.objectContaining({
        config: {
          prompt_rules: { platform: null, current_request: null, memory: null },
          prompt_preset_id: 'system',
          prompt_presets: [],
        },
      })
    );
    expect(wrapper.get('#ai-platform-prompt').element.disabled).toBe(false);
    wrapper.unmount();
  });
});
