import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import WhatsappProfileAPI from 'dashboard/api/whatsappProfile';
import ProfilePhotoEditor from 'next/avatar/ProfilePhotoEditor.vue';
import WhatsmeowProfilePage from '../WhatsmeowProfilePage.vue';
import WhatsmeowBusinessProfile from '../WhatsmeowBusinessProfile.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/whatsappProfile', () => ({
  default: {
    show: vi.fn(),
    update: vi.fn(),
    updatePhoto: vi.fn(),
    removePhoto: vi.fn(),
  },
}));
const props = { inbox: { id: 27, channel_type: 'Channel::Whatsmeow' } };
let profile;
const global = {
  plugins: [
    createStore({
      getters: {
        'inboxes/getInbox': () => () => ({
          channel_type: 'Channel::Whatsmeow',
        }),
      },
    }),
  ],
  stubs: {
    teleport: true,
    ProfilePhotoEditor: {
      props: ['file', 'saving'],
      emits: ['close', 'confirm'],
      template: '<div />',
    },
  },
};
beforeEach(() => {
  profile = {
    name: 'Owner',
    about: 'Available',
    phone: '+5511999991111',
    photo_url: 'https://example.com/current.jpg',
    photo_status: 'available',
    is_business: false,
  };
  WhatsappProfileAPI.show.mockResolvedValue({ data: profile });
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
});

describe('WhatsApp profile settings', () => {
  it('shows the real profile on opening and refreshes changes from the phone', async () => {
    const wrapper = mount(WhatsmeowProfilePage, { props, global });
    await flushPromises();
    expect(wrapper.text()).toContain('Owner');
    expect(wrapper.text()).toContain('Available');
    expect(wrapper.text()).toContain('+5511999991111');
    WhatsappProfileAPI.show.mockResolvedValueOnce({
      data: { ...profile, name: 'Changed on phone', photo_url: '' },
    });
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('WHATSAPP_PROFILE.REFRESH'))
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Changed on phone');
    expect(WhatsappProfileAPI.show).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('edits about without sending unrelated name or business changes', async () => {
    WhatsappProfileAPI.update.mockResolvedValue({ data: { success: true } });
    const wrapper = mount(WhatsmeowProfilePage, { props, global });
    await flushPromises();
    await wrapper
      .findAll('button[aria-label]')
      .filter(button =>
        button.attributes('aria-label').includes('WHATSAPP_PROFILE.EDIT_FIELD')
      )[1]
      .trigger('click');
    await wrapper.get('textarea').setValue('New about');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(WhatsappProfileAPI.update).toHaveBeenCalledWith(27, {
      about: 'New about',
    });
    wrapper.unmount();
  });

  it('does not claim success when a save fails', async () => {
    WhatsappProfileAPI.update.mockRejectedValue(new Error('Disconnected'));
    const wrapper = mount(WhatsmeowProfilePage, { props, global });
    await flushPromises();
    await wrapper
      .findAll('button[aria-label]')
      .filter(button =>
        button.attributes('aria-label').includes('WHATSAPP_PROFILE.EDIT_FIELD')
      )[0]
      .trigger('click');
    await wrapper.get('input[maxlength="25"]').setValue('New name');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith('WHATSAPP_PROFILE.SAVE_ERROR');
    expect(wrapper.get('input[maxlength="25"]').element.value).toBe('New name');
    wrapper.unmount();
  });

  it('uploads only the confirmed crop, not the original selected file', async () => {
    WhatsappProfileAPI.updatePhoto.mockResolvedValue({
      data: { photo_url: 'https://example.com/new.jpg' },
    });
    const wrapper = mount(WhatsmeowProfilePage, { props, global });
    await flushPromises();
    const input = wrapper.get('input[type="file"]');
    Object.defineProperty(input.element, 'files', {
      configurable: true,
      value: [new File(['image'], 'photo.png', { type: 'image/png' })],
    });
    await input.trigger('change');
    expect(WhatsappProfileAPI.updatePhoto).not.toHaveBeenCalled();
    wrapper
      .getComponent(ProfilePhotoEditor)
      .vm.$emit('confirm', 'cropped-jpeg');
    await flushPromises();
    expect(WhatsappProfileAPI.updatePhoto).toHaveBeenCalledWith(
      27,
      'cropped-jpeg'
    );
    expect(wrapper.findComponent(ProfilePhotoEditor).exists()).toBe(false);
    wrapper.unmount();
  });

  it('rejects non-image files without opening the cropper', async () => {
    const wrapper = mount(WhatsmeowProfilePage, { props, global });
    await flushPromises();
    const input = wrapper.get('input[type="file"]');
    Object.defineProperty(input.element, 'files', {
      configurable: true,
      value: [new File(['pdf'], 'file.pdf', { type: 'application/pdf' })],
    });
    await input.trigger('change');
    expect(wrapper.findComponent(ProfilePhotoEditor).exists()).toBe(false);
    expect(useAlert).toHaveBeenCalledWith('WHATSAPP_PROFILE.FILE_ERROR');
    wrapper.unmount();
  });

  it('requires explicit confirmation before removing the existing photo', async () => {
    WhatsappProfileAPI.removePhoto.mockResolvedValue({
      data: { photo_url: '', photo_status: 'none' },
    });
    const wrapper = mount(WhatsmeowProfilePage, { props, global });
    await flushPromises();
    await wrapper.get('button[aria-haspopup="menu"]').trigger('click');
    await wrapper
      .findAll('button[role="menuitem"]')
      .find(button => button.text() === 'WHATSAPP_PROFILE.REMOVE_PHOTO')
      .trigger('click');
    expect(WhatsappProfileAPI.removePhoto).not.toHaveBeenCalled();
    await wrapper.get('dialog[open] form').trigger('submit');
    await flushPromises();
    expect(WhatsappProfileAPI.removePhoto).toHaveBeenCalledWith(27);
    wrapper.unmount();
  });

  it('shows commercial fields only for WhatsApp Business accounts', async () => {
    WhatsappProfileAPI.show.mockResolvedValueOnce({
      data: {
        ...profile,
        is_business: true,
        business: {
          address: 'Address',
          websites: ['https://example.com'],
          hours: { timezone: 'America/Sao_Paulo', days: [] },
        },
      },
    });
    const wrapper = mount(WhatsmeowProfilePage, { props, global });
    await flushPromises();
    expect(wrapper.findComponent(WhatsmeowBusinessProfile).exists()).toBe(true);
    expect(wrapper.get('input[maxlength="512"]').element.value).toBe('Address');
    wrapper.unmount();
  });

  it('renders a connection error and permits a new load', async () => {
    WhatsappProfileAPI.show.mockRejectedValueOnce(new Error('Disconnected'));
    const wrapper = mount(WhatsmeowProfilePage, { props, global });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'WHATSAPP_PROFILE.LOAD_ERROR'
    );
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('WHATSAPP_PROFILE.RETRY'))
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Owner');
    wrapper.unmount();
  });
});

describe('Business hours', () => {
  it('preserves existing hours when only the address or sites change', async () => {
    const wrapper = mount(WhatsmeowBusinessProfile, {
      props: {
        profile: {
          hours: {
            timezone: 'America/Sao_Paulo',
            days: [
              {
                day: 'mon',
                mode: 'specific_hours',
                open: '540',
                close: '1080',
              },
            ],
          },
        },
      },
    });
    await wrapper.get('input[maxlength="512"]').setValue('New address');
    await wrapper.get('form').trigger('submit');
    const [business] = wrapper.emitted('save')[0];
    expect(business.address).toBe('New address');
    expect(business).not.toHaveProperty('hours');
    wrapper.unmount();
  });

  it('converts opening times to WhatsApp minutes and omits closed days', async () => {
    const wrapper = mount(WhatsmeowBusinessProfile, {
      props: {
        profile: {
          hours: {
            timezone: 'America/Sao_Paulo',
            days: [
              {
                day: 'mon',
                mode: 'specific_hours',
                open: '540',
                close: '1080',
              },
            ],
          },
        },
      },
    });
    await wrapper.findAll('input[type="time"]')[0].setValue('10:30');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')[0][0].hours).toEqual({
      timezone: 'America/Sao_Paulo',
      days: [{ day: 'mon', mode: 'specific_hours', open: 630, close: 1080 }],
    });
    wrapper.unmount();
  });
});
