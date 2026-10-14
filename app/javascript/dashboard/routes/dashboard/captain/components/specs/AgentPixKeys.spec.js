import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/marcosxAi';
import AgentPixKeys from '../AgentPixKeys.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: {
    getPixKeys: vi.fn(),
    savePixKey: vi.fn(),
    deletePixKey: vi.fn(),
  },
}));
const keys = [
  {
    id: 1,
    title: 'Main account',
    key_type: 'EMAIL',
    key: 'main@example.com',
    merchant_name: 'Test holder',
    description: 'Direct purchases',
    enabled: true,
    primary: true,
  },
  {
    id: 2,
    title: 'Alternative',
    key_type: 'PHONE',
    key: '+5511999999999',
    merchant_name: 'Test holder',
    description: '',
    enabled: true,
    primary: false,
  },
  {
    id: 3,
    title: 'Disabled',
    key_type: 'EMAIL',
    key: 'disabled@example.com',
    merchant_name: 'Test holder',
    description: '',
    enabled: false,
    primary: false,
  },
];
const options = {
  props: { agentId: 7 },
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
  API.getPixKeys.mockResolvedValue({ data: { pix_keys: keys } });
  API.savePixKey.mockResolvedValue({ data: { pix_keys: keys } });
  API.deletePixKey.mockResolvedValue({ data: { pix_keys: [] } });
});

it('loads keys for this agent and blocks activation of a third while keeping edit available', async () => {
  const wrapper = mount(AgentPixKeys, options);
  await flushPromises();
  expect(API.getPixKeys).toHaveBeenCalledWith(7);
  const switches = wrapper.findAll('article button[role="switch"]');
  expect(switches[0].attributes('aria-checked')).toBe('true');
  expect(switches[2].attributes('disabled')).toBeDefined();
  await switches[0].trigger('click');
  await flushPromises();
  expect(API.savePixKey).toHaveBeenCalledWith(7, 1, { enabled: false });
  wrapper.unmount();
});

it('keeps details and type-specific native previews, saves without sending and supports a second phone key', async () => {
  const wrapper = mount(AgentPixKeys, options);
  await flushPromises();
  await wrapper
    .findAll('button[aria-label="MARCOX_AI.PIX.EDIT"]')[1]
    .trigger('click');
  expect(wrapper.find('select').exists()).toBe(false);
  expect(wrapper.get('[aria-haspopup="listbox"]').text()).toBe(
    'CONVERSATION.WHATSMEOW_PIX.KEY_TYPES.PHONE'
  );
  const inputs = wrapper.findAll('input');
  await inputs[0].setValue('Second phone');
  await inputs[1].setValue('+5511988888888');
  await inputs[2].setValue('Another holder');
  await wrapper.get('textarea').setValue('Fallback for the main account');
  expect(wrapper.text()).toContain('+5511988888888');
  await wrapper.findAll('form')[0].trigger('submit');
  await flushPromises();
  expect(API.savePixKey).toHaveBeenCalledWith(
    7,
    2,
    expect.objectContaining({
      title: 'Second phone',
      key_type: 'PHONE',
      key: '+5511988888888',
      merchant_name: 'Another holder',
      enabled: true,
    })
  );
  wrapper.unmount();
});

it('shows backend validation failures inside the editor and leaves the submitted data available', async () => {
  API.savePixKey.mockRejectedValue({
    response: { data: { error: 'Invalid Pix key' } },
  });
  const wrapper = mount(AgentPixKeys, options);
  await flushPromises();
  await wrapper
    .findAll('button[aria-label="MARCOX_AI.PIX.EDIT"]')[0]
    .trigger('click');
  await wrapper.findAll('form')[0].trigger('submit');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe('Invalid Pix key');
  expect(wrapper.findAll('input')[1].element.value).toBe(keys[0].key);
  wrapper.unmount();
});

it('selects Pix types with the Chatwoot icon menu and saves the selected type', async () => {
  const wrapper = mount(AgentPixKeys, options);
  await flushPromises();
  await wrapper
    .findAll('button[aria-label="MARCOX_AI.PIX.EDIT"]')[1]
    .trigger('click');
  const trigger = wrapper.get('[aria-haspopup="listbox"]');
  expect(trigger.find('.i-lucide-smartphone').exists()).toBe(true);
  await trigger.trigger('click');
  expect(wrapper.findAll('[role="option"]')).toHaveLength(4);
  expect(
    wrapper.get('[role="listbox"]').find('.i-lucide-id-card').exists()
  ).toBe(true);
  await wrapper.findAll('[role="option"]')[2].trigger('click');
  expect(wrapper.find('[role="listbox"]').exists()).toBe(false);
  expect(trigger.find('.i-lucide-mail').exists()).toBe(true);
  await wrapper.findAll('input')[1].setValue('other@example.com');
  await wrapper.findAll('form')[0].trigger('submit');
  await flushPromises();
  expect(API.savePixKey).toHaveBeenCalledWith(
    7,
    2,
    expect.objectContaining({ key_type: 'EMAIL', key: 'other@example.com' })
  );
  wrapper.unmount();
});

it('keeps Escape inside the open menu and returns keyboard focus to its trigger', async () => {
  const wrapper = mount(AgentPixKeys, { ...options, attachTo: document.body });
  await flushPromises();
  await wrapper
    .findAll('button[aria-label="MARCOX_AI.PIX.EDIT"]')[1]
    .trigger('click');
  const trigger = wrapper.get('[aria-haspopup="listbox"]');
  await trigger.trigger('keydown', { key: 'ArrowDown' });
  await flushPromises();
  expect(document.activeElement).toBe(
    wrapper.findAll('[role="option"]')[0].element
  );
  await wrapper
    .get('[role="listbox"]')
    .trigger('keydown', { key: 'ArrowDown' });
  expect(document.activeElement).toBe(
    wrapper.findAll('[role="option"]')[1].element
  );
  const escaped = vi.fn();
  wrapper.get('form').element.addEventListener('keydown', escaped);
  await wrapper.get('[role="listbox"]').trigger('keydown', { key: 'Escape' });
  expect(escaped).not.toHaveBeenCalled();
  expect(wrapper.find('[role="listbox"]').exists()).toBe(false);
  expect(document.activeElement).toBe(trigger.element);
  expect(API.savePixKey).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('promotes an alternative explicitly and requires the native delete confirmation', async () => {
  const wrapper = mount(AgentPixKeys, options);
  await flushPromises();
  const primary = wrapper
    .findAll('button')
    .find(button => button.text().includes('MARCOX_AI.PIX.MAKE_PRIMARY'));
  await primary.trigger('click');
  await flushPromises();
  expect(API.savePixKey).toHaveBeenCalledWith(7, 2, { primary: true });
  await wrapper
    .findAll('button[aria-label="MARCOX_AI.PIX.DELETE"]')[0]
    .trigger('click');
  expect(API.deletePixKey).not.toHaveBeenCalled();
  await wrapper.findAll('form')[1].trigger('submit');
  await flushPromises();
  expect(API.deletePixKey).toHaveBeenCalledWith(7, 1);
  wrapper.unmount();
});

it('ignores late loading responses after changing agents', async () => {
  let resolveOld;
  API.getPixKeys.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  const wrapper = mount(AgentPixKeys, options);
  await wrapper.setProps({ agentId: 8 });
  await flushPromises();
  resolveOld({
    data: { pix_keys: [{ ...keys[0], title: 'Old agent secret' }] },
  });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Old agent secret');
  expect(API.getPixKeys).toHaveBeenCalledWith(8);
  wrapper.unmount();
});
