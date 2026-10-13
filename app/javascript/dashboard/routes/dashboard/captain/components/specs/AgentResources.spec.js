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
const options = {
  props: { agentId: 3 },
  global: {
    stubs: {
      Dialog: {
        props: ['disableConfirmButton'],
        setup(_, { expose }) {
          expose({ open() {}, close() {} });
        },
        template: '<div><slot /></div>',
      },
    },
  },
};
beforeEach(() => {
  vi.clearAllMocks();
  API.getResources.mockResolvedValue({
    data: { resources: [item], total: 1, per_page: 24 },
  });
  API.saveResource.mockResolvedValue({ data: {} });
  API.deleteResource.mockResolvedValue({});
});

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
