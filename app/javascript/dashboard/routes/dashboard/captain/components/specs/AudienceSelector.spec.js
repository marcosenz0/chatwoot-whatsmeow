import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/marcosxAi';
import AudienceSelector from '../AudienceSelector.vue';
import { defaultAudience, audiencePayload } from '../audience';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: { getAudienceContacts: vi.fn() },
}));

beforeEach(() => {
  vi.clearAllMocks();
  API.getAudienceContacts.mockResolvedValue({
    data: {
      contacts: [
        { id: 3, name: 'Anna' },
        { id: 4, name: 'Maria' },
      ],
    },
  });
});

it('defaults quick additions to exactly the supplied conversation and global additions to the selected agent', () => {
  expect(defaultAudience(false, 92)).toMatchObject({
    audience: 'conversation',
    conversation_id: 92,
    contact_ids: [],
  });
  expect(audiencePayload(defaultAudience(true, 92))).toEqual({
    audience: 'global',
    conversation_id: null,
    contact_ids: [],
  });
});

it('adds and removes specific contacts without a native select and clears their IDs when switching to global', async () => {
  const wrapper = mount(AudienceSelector, {
    props: {
      agentId: 1,
      modelValue: {
        audience: 'contacts',
        contact_ids: [3],
        audience_contacts: [{ id: 3, name: 'Anna' }],
      },
    },
  });
  await flushPromises();
  expect(API.getAudienceContacts).toHaveBeenCalledWith(1, '', {
    signal: expect.any(AbortSignal),
  });
  expect(wrapper.find('select').exists()).toBe(false);
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Maria')
    .trigger('click');
  let [value] = wrapper.emitted('update:modelValue').at(-1);
  expect(value.contact_ids).toEqual([3, 4]);
  await wrapper.setProps({ modelValue: value });
  await wrapper
    .findAll('button')
    .find(button =>
      button.attributes('aria-label')?.includes('MARCOX_AI.AUDIENCE.REMOVE')
    )
    .trigger('click');
  [value] = wrapper.emitted('update:modelValue').at(-1);
  expect(value.contact_ids).toEqual([4]);
  await wrapper.setProps({ modelValue: value });
  wrapper
    .findComponent({ name: 'AiSelect' })
    .vm.$emit('update:modelValue', 'global');
  await flushPromises();
  expect(wrapper.emitted('update:modelValue').at(-1)[0]).toMatchObject({
    audience: 'global',
    contact_ids: [],
    conversation_id: null,
  });
  wrapper.unmount();
});

it('cancels a contact search when changing agents', async () => {
  API.getAudienceContacts.mockImplementationOnce(() => new Promise(() => {}));
  const wrapper = mount(AudienceSelector, {
    props: {
      agentId: 1,
      modelValue: { audience: 'contacts', contact_ids: [] },
    },
  });
  const oldSignal = API.getAudienceContacts.mock.calls[0][2].signal;
  await wrapper.setProps({ agentId: 2 });
  await flushPromises();
  expect(oldSignal.aborted).toBe(true);
  expect(API.getAudienceContacts).toHaveBeenLastCalledWith(2, '', {
    signal: expect.any(AbortSignal),
  });
  wrapper.unmount();
});
