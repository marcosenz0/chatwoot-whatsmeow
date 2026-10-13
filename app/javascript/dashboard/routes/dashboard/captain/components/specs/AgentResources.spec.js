import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/marcosxAi';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AgentResources from '../AgentResources.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: {
    getResources: vi.fn(),
    saveResource: vi.fn(),
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
      createObjectURL: vi.fn(selected => `blob:${selected.name}`),
      revokeObjectURL: vi.fn(),
    })
  );
  API.getResources.mockResolvedValue({
    data: { resources: [item], total: 1, per_page: 24 },
  });
  API.saveResource.mockResolvedValue({ data: {} });
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

it('saves a described link through multipart without embedding its URL in instructions', async () => {
  const wrapper = mount(AgentResources, options);
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('RESOURCES.ADD'))
    .trigger('click');
  const fileInput = wrapper.get('input[type="file"]');
  Object.defineProperty(fileInput.element, 'files', {
    value: [new File(['image'], 'discarded.png', { type: 'image/png' })],
  });
  await fileInput.trigger('change');
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('KIND_LINK'))
    .trigger('click');
  await wrapper.get('input[maxlength="120"]').setValue('Reference link');
  await wrapper
    .get('textarea')
    .setValue('Send when the contact asks for a reference');
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
  expect(form.get('resource[description]')).toContain('asks for a reference');
  wrapper.unmount();
});

it('requires a file and context before uploading and sends the selected file bytes', async () => {
  const wrapper = mount(AgentResources, options);
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('RESOURCES.ADD'))
    .trigger('click');
  await wrapper.get('input[maxlength="120"]').setValue('Photo');
  await wrapper.get('textarea').setValue('A reference photo');
  expect(
    wrapper.findAllComponents(Dialog)[0].props('disableConfirmButton')
  ).toBe(true);
  const input = wrapper.get('input[type="file"]');
  const file = new File(['image'], 'photo.png', { type: 'image/png' });
  Object.defineProperty(input.element, 'files', { value: [file] });
  await input.trigger('change');
  wrapper.findAllComponents(Dialog)[0].vm.$emit('confirm');
  await flushPromises();
  expect(API.saveResource.mock.calls[0][2].get('resource[file]').name).toBe(
    'photo.png'
  );
  wrapper.unmount();
});

it('previews an image, replaces it with a video frame and clears the selection with the X', async () => {
  const wrapper = mount(AgentResources, options);
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('RESOURCES.ADD'))
    .trigger('click');
  const input = wrapper.get('input[type="file"]');
  Object.defineProperty(input.element, 'files', {
    configurable: true,
    value: [new File(['image'], 'photo.png', { type: 'image/png' })],
  });
  await input.trigger('change');
  await flushPromises();
  expect(URL.createObjectURL).toHaveBeenCalledWith(input.element.files[0]);
  expect(wrapper.get('img[alt="photo.png"]').attributes('src')).toBe(
    'blob:photo.png'
  );
  Object.defineProperty(input.element, 'files', {
    configurable: true,
    value: [new File(['video'], 'clip.mp4', { type: 'video/mp4' })],
  });
  await input.trigger('change');
  expect(wrapper.find('img[alt="photo.png"]').exists()).toBe(false);
  expect(wrapper.get('video').attributes('src')).toBe('blob:clip.mp4#t=0.001');
  expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:photo.png');
  await wrapper
    .get('button[aria-label="MARCOX_AI.RESOURCES.REMOVE_SELECTION"]')
    .trigger('click');
  expect(wrapper.find('video').exists()).toBe(false);
  expect(input.element.value).toBe('');
  expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:clip.mp4');
  expect(
    wrapper.findAllComponents(Dialog)[0].props('disableConfirmButton')
  ).toBe(true);
  expect(API.saveResource).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('shows an existing media preview and restores it when a replacement is removed', async () => {
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
  Object.defineProperty(input.element, 'files', {
    value: [new File(['video'], 'replacement.mp4', { type: 'video/mp4' })],
  });
  await input.trigger('change');
  expect(wrapper.find('video').exists()).toBe(true);
  await wrapper
    .get('button[aria-label="MARCOX_AI.RESOURCES.REMOVE_SELECTION"]')
    .trigger('click');
  expect(wrapper.get('img[alt="saved.png"]').attributes('src')).toBe(
    '/saved.png'
  );
  expect(API.deleteResource).not.toHaveBeenCalled();
  wrapper.unmount();
});
