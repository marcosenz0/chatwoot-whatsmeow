import { flushPromises, shallowMount } from '@vue/test-utils';
import GroupsAPI from 'dashboard/api/whatsmeowGroups';
import GroupContactPicker from '../GroupContactPicker.vue';

vi.mock('dashboard/api/whatsmeowGroups', () => ({
  default: { contacts: vi.fn() },
}));

const selected = { jid: '556392977347@s.whatsapp.net', name: 'Note12' };
const other = { jid: '556391174954@s.whatsapp.net', name: 'Poco' };

beforeEach(() => {
  GroupsAPI.contacts.mockResolvedValue({
    data: { contacts: [selected, other], has_more: false },
  });
});

describe('GroupContactPicker', () => {
  it('preserves members when returning to the contact selection step', async () => {
    const wrapper = shallowMount(GroupContactPicker, {
      props: { inboxId: 28, modelValue: [selected] },
    });
    await flushPromises();
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(wrapper.get('button[aria-pressed="true"]').text()).toContain('Note12');
    await wrapper.get('button[aria-pressed="false"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual([selected, other]);
    wrapper.unmount();
  });

  it('hides the connected number and existing group members', async () => {
    GroupsAPI.contacts.mockResolvedValue({
      data: { contacts: [{ ...selected, is_self: true }, other], has_more: false },
    });
    const wrapper = shallowMount(GroupContactPicker, {
      props: { inboxId: 28, excluded: [other.jid] },
    });
    await flushPromises();
    expect(wrapper.findAll('button[aria-pressed]')).toHaveLength(0);
    wrapper.unmount();
  });

  it('resets members only when the user chooses another WhatsApp inbox', async () => {
    const wrapper = shallowMount(GroupContactPicker, {
      props: { inboxId: 28, modelValue: [selected] },
    });
    await flushPromises();
    await wrapper.setProps({ inboxId: 15 });
    await flushPromises();
    expect(wrapper.emitted('update:modelValue')).toEqual([[[]]]);
    expect(GroupsAPI.contacts).toHaveBeenLastCalledWith(
      15,
      { q: '', offset: 0 },
      { signal: expect.any(AbortSignal) }
    );
    wrapper.unmount();
  });
});
