import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/marcosxAi';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AgentResources from '../AgentResources.vue';
import AudienceSelector from '../AudienceSelector.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: {
    getResources: vi.fn(),
    saveResource: vi.fn(),
    saveResourceBatch: vi.fn(),
    deleteResource: vi.fn(),
  },
}));
const item = {
  id: 7,
  title: 'Information sheet',
  description: 'Send when someone asks for the sheet',
  kind: 'link',
  url: 'https://example.com/sheet',
  enabled: true,
};
const NativeURL = URL;
const options = {
  props: { agentId: 3 },
  global: {
    stubs: {
      Dialog: {
        props: ['disableConfirmButton'],
        setup(_, { expose }) {
          expose({ open() {}, close() {} });
        },
        template: '<form @submit.prevent="$emit(\'confirm\')"><slot /></form>',
      },
    },
  },
};
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal(
    'URL',
    Object.assign(class extends NativeURL {}, {
      createObjectURL: vi.fn(file => `blob:${file.name}`),
      revokeObjectURL: vi.fn(),
    })
  );
  API.getResources.mockResolvedValue({
    data: { resources: [item], total: 1, per_page: 24, limit: 100 },
  });
  API.saveResource.mockResolvedValue({ data: {} });
  API.saveResourceBatch.mockResolvedValue({ data: {} });
  API.deleteResource.mockResolvedValue({});
});
afterEach(() => vi.unstubAllGlobals());

it('loads and disables items only for the selected agent', async () => {
  const wrapper = mount(AgentResources, options);
  await flushPromises();
  expect(wrapper.text()).toContain(item.description);
  expect(API.getResources).toHaveBeenCalledWith(3, { search: '', page: 1 });
  await wrapper
    .get('button[aria-label="MARCOX_AI.RESOURCES.DISABLE"]')
    .trigger('click');
  await flushPromises();
  expect(API.saveResource).toHaveBeenCalledWith(3, 7, {
    resource: { enabled: false },
  });
  wrapper.unmount();
});

it('saves a described link without sending the unsaved file selection', async () => {
  const wrapper = mount(AgentResources, options);
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(b => b.text().includes('RESOURCES.ADD'))
    .trigger('click');
  const input = wrapper.get('input[type="file"]');
  Object.defineProperty(input.element, 'files', {
    value: [new File(['image'], 'discarded.png', { type: 'image/png' })],
  });
  await input.trigger('change');
  await wrapper
    .findAll('button')
    .find(b => b.text().includes('KIND_LINK'))
    .trigger('click');
  await wrapper.get('input[maxlength="120"]').setValue('Reference link');
  await wrapper.get('textarea').setValue('Send when asked for a reference');
  await wrapper
    .get('input[type="url"]')
    .setValue('https://example.com/reference');
  wrapper.findAllComponents(Dialog)[0].vm.$emit('confirm');
  await flushPromises();
  const [agentId, id, form] = API.saveResource.mock.calls[0];
  expect(agentId).toBe(3);
  expect(id).toBeUndefined();
  expect(form.get('resource[url]')).toBe('https://example.com/reference');
  expect(form.get('resource[file]')).toBeNull();
  expect(API.saveResourceBatch).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('keeps successive and multiple selections, independent descriptions, audiences and availability, and submits one complete batch', async () => {
  const wrapper = mount(AgentResources, {
    ...options,
    props: { ...options.props, conversationId: 92, globalScope: false },
  });
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(b => b.text().includes('RESOURCES.ADD'))
    .trigger('click');
  const input = wrapper.get('input[type="file"]');
  expect(input.attributes()).toHaveProperty('multiple');
  Object.defineProperty(input.element, 'files', {
    configurable: true,
    value: [
      new File(['one'], 'one.png', { type: 'image/png' }),
      new File(['two'], 'two.mp4', { type: 'video/mp4' }),
    ],
  });
  await input.trigger('change');
  await wrapper.get('textarea').setValue('First photo context');
  Object.defineProperty(input.element, 'files', {
    configurable: true,
    value: ['three', 'four', 'five'].map(
      name => new File([name], `${name}.png`, { type: 'image/png' })
    ),
  });
  await input.trigger('change');
  expect(wrapper.findAll('[data-testid="resource-draft"]')).toHaveLength(5);
  expect(wrapper.get('img[alt="one.png"]').attributes('src')).toBe(
    'blob:one.png'
  );
  expect(wrapper.get('textarea').element.value).toBe('First photo context');
  expect(
    wrapper.findAllComponents(Dialog)[0].props('disableConfirmButton')
  ).toBe(true);
  const tiles = wrapper.findAll('[data-testid="resource-draft"]');
  await tiles[1].get('button').trigger('click');
  expect(tiles[1].get('button').attributes('aria-pressed')).toBe('true');
  expect(wrapper.get('textarea').element.value).toBe('');
  await wrapper.get('textarea').setValue('Video presentation context');
  const scope = wrapper.findComponent(AudienceSelector);
  scope.vm.$emit('update:modelValue', {
    ...scope.props('modelValue'),
    audience: 'global',
    conversation_id: null,
  });
  await flushPromises();
  await wrapper.get('button[role="switch"]').trigger('click');
  await tiles[3].get('button').trigger('click');
  await wrapper.get('textarea').setValue('Fourth photo context');
  await tiles[4].get('button').trigger('click');
  await wrapper.get('textarea').setValue('Fifth photo context');
  await tiles[0].get('button').trigger('click');
  expect(wrapper.get('textarea').element.value).toBe('First photo context');
  await tiles[2].findAll('button')[1].trigger('click');
  expect(wrapper.findAll('[data-testid="resource-draft"]')).toHaveLength(4);
  expect(wrapper.get('textarea').element.value).toBe('First photo context');
  expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:three.png');
  expect(
    wrapper.findAllComponents(Dialog)[0].props('disableConfirmButton')
  ).toBe(false);
  wrapper.findAllComponents(Dialog)[0].vm.$emit('confirm');
  await flushPromises();
  const [agentId, form] = API.saveResourceBatch.mock.calls[0];
  expect(agentId).toBe(3);
  expect(form.getAll('resources[][file]').map(file => file.name)).toEqual([
    'one.png',
    'two.mp4',
    'four.png',
    'five.png',
  ]);
  expect(form.getAll('resources[][description]')).toEqual([
    'First photo context',
    'Video presentation context',
    'Fourth photo context',
    'Fifth photo context',
  ]);
  expect(form.getAll('resources[][enabled]')).toEqual([
    'true',
    'false',
    'true',
    'true',
  ]);
  expect(form.getAll('resources[][audience]')).toEqual([
    'conversation',
    'global',
    'conversation',
    'conversation',
  ]);
  expect(form.getAll('resources[][conversation_id]')).toEqual([
    '92',
    '92',
    '92',
  ]);
  expect(API.saveResource).not.toHaveBeenCalled();
  wrapper.unmount();
  expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:one.png');
  expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:five.png');
});

it('keeps the remaining active file after removal and clears every object URL on cancellation', async () => {
  const wrapper = mount(AgentResources, options);
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(b => b.text().includes('RESOURCES.ADD'))
    .trigger('click');
  const input = wrapper.get('input[type="file"]');
  Object.defineProperty(input.element, 'files', {
    value: ['one', 'two'].map(
      name => new File([name], `${name}.png`, { type: 'image/png' })
    ),
  });
  await input.trigger('change');
  await wrapper.get('textarea').setValue('First description');
  await wrapper
    .findAll('[data-testid="resource-draft"]')[1]
    .get('button')
    .trigger('click');
  await wrapper.get('textarea').setValue('Second description');
  await wrapper
    .findAll('[data-testid="resource-draft"]')[1]
    .findAll('button')[1]
    .trigger('click');
  expect(wrapper.get('textarea').element.value).toBe('First description');
  wrapper.findAllComponents(Dialog)[0].vm.$emit('close');
  await flushPromises();
  expect(wrapper.findAll('[data-testid="resource-draft"]')).toHaveLength(0);
  expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:one.png');
  expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:two.png');
  expect(API.saveResourceBatch).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('restores an existing file when its replacement is removed and keeps the single-item update contract', async () => {
  API.getResources.mockResolvedValue({
    data: {
      resources: [
        {
          ...item,
          kind: 'image',
          file_name: 'saved.png',
          file_url: '/saved.png',
        },
      ],
      total: 1,
      per_page: 24,
      limit: 100,
    },
  });
  const wrapper = mount(AgentResources, options);
  await flushPromises();
  await wrapper
    .get('button[aria-label="MARCOX_AI.RESOURCES.EDIT"]')
    .trigger('click');
  expect(wrapper.get('img[alt="saved.png"]').attributes('src')).toBe(
    '/saved.png'
  );
  const input = wrapper.get('input[type="file"]');
  expect(input.attributes()).not.toHaveProperty('multiple');
  Object.defineProperty(input.element, 'files', {
    value: [new File(['video'], 'replacement.mp4', { type: 'video/mp4' })],
  });
  await input.trigger('change');
  await wrapper
    .findAll('[data-testid="resource-draft"]')[0]
    .findAll('button')[1]
    .trigger('click');
  expect(wrapper.get('img[alt="saved.png"]').attributes('src')).toBe(
    '/saved.png'
  );
  expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:replacement.mp4');
  await wrapper.get('textarea').setValue('Updated saved photo context');
  wrapper.findAllComponents(Dialog)[0].vm.$emit('confirm');
  await flushPromises();
  expect(API.saveResource.mock.calls[0][1]).toBe(7);
  expect(API.saveResource.mock.calls[0][2].get('resource[file]')).toBeNull();
  expect(API.saveResource.mock.calls[0][2].get('resource[description]')).toBe(
    'Updated saved photo context'
  );
  expect(API.deleteResource).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('preserves the draft when a batch is rejected and permits retry without clearing descriptions', async () => {
  API.saveResourceBatch.mockRejectedValueOnce({
    response: { data: { error: 'Rejected batch' } },
  });
  const wrapper = mount(AgentResources, options);
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(b => b.text().includes('RESOURCES.ADD'))
    .trigger('click');
  const input = wrapper.get('input[type="file"]');
  Object.defineProperty(input.element, 'files', {
    value: [new File(['image'], 'photo.png', { type: 'image/png' })],
  });
  await input.trigger('change');
  await wrapper.get('textarea').setValue('Photo context');
  wrapper.findAllComponents(Dialog)[0].vm.$emit('confirm');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe('Rejected batch');
  expect(wrapper.get('textarea').element.value).toBe('Photo context');
  expect(wrapper.findAll('[data-testid="resource-draft"]')).toHaveLength(1);
  wrapper.findAllComponents(Dialog)[0].vm.$emit('confirm');
  await flushPromises();
  expect(API.saveResourceBatch).toHaveBeenCalledTimes(2);
  wrapper.unmount();
});

it('rejects a selection beyond remaining catalog capacity while retaining existing drafts', async () => {
  API.getResources.mockResolvedValue({
    data: { resources: [item], total: 99, per_page: 24, limit: 100 },
  });
  const wrapper = mount(AgentResources, options);
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(b => b.text().includes('RESOURCES.ADD'))
    .trigger('click');
  const input = wrapper.get('input[type="file"]');
  Object.defineProperty(input.element, 'files', {
    configurable: true,
    value: [new File(['one'], 'one.png', { type: 'image/png' })],
  });
  await input.trigger('change');
  await wrapper.get('textarea').setValue('Preserved description');
  Object.defineProperty(input.element, 'files', {
    configurable: true,
    value: [new File(['two'], 'two.png', { type: 'image/png' })],
  });
  await input.trigger('change');
  expect(wrapper.findAll('[data-testid="resource-draft"]')).toHaveLength(1);
  expect(wrapper.get('textarea').element.value).toBe('Preserved description');
  expect(wrapper.get('[role="alert"]').text()).toContain('BATCH_LIMIT');
  wrapper.unmount();
});
