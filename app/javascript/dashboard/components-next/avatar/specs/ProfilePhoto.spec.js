import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import WhatsappProfileAPI from 'dashboard/api/whatsappProfile';
import { clampCrop, cropToJpeg } from 'dashboard/helper/profilePhotoCrop';
import ProfilePhotoAvatar from '../ProfilePhotoAvatar.vue';
import ProfilePhotoViewer from '../ProfilePhotoViewer.vue';
import ProfileCamera from '../ProfileCamera.vue';
import ProfilePhotoEditor from '../ProfilePhotoEditor.vue';

vi.mock('dashboard/api/whatsappProfile', () => ({
  default: { contactPhoto: vi.fn(), photo: vi.fn() },
}));
let store;
beforeEach(() => {
  store = createStore({
    getters: {
      'inboxes/getInbox': () => () => ({ channel_type: 'Channel::Whatsmeow' }),
    },
  });
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
});

describe('Full profile photo', () => {
  it('fetches a current full photo and keeps the thumbnail out of the viewer', async () => {
    WhatsappProfileAPI.contactPhoto.mockResolvedValue({
      data: {
        photo_url: 'https://example.com/full.jpg',
        photo_status: 'available',
      },
    });
    const wrapper = mount(ProfilePhotoAvatar, {
      props: {
        src: 'thumbnail.jpg',
        name: 'Contact',
        contactId: 10,
        inboxId: 27,
      },
      global: { plugins: [store] },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(WhatsappProfileAPI.contactPhoto).toHaveBeenCalledWith(10, 27);
    expect(wrapper.getComponent(ProfilePhotoViewer).props('src')).toBe(
      'https://example.com/full.jpg'
    );
    wrapper.unmount();
  });

  it('does not expose the saved thumbnail when WhatsApp hides the photo', async () => {
    WhatsappProfileAPI.contactPhoto.mockResolvedValue({
      data: { photo_url: '', photo_status: 'hidden' },
    });
    const wrapper = mount(ProfilePhotoAvatar, {
      props: {
        src: 'old-private-photo.jpg',
        name: 'Contact',
        contactId: 10,
        inboxId: 27,
      },
      global: { plugins: [store] },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.getComponent(ProfilePhotoViewer).props('src')).toBe('');
    expect(wrapper.getComponent(ProfilePhotoViewer).props('photoStatus')).toBe(
      'hidden'
    );
    wrapper.unmount();
  });

  it('fetches the connected number photo for outgoing voice messages', async () => {
    WhatsappProfileAPI.photo.mockResolvedValue({
      data: { photo_url: 'https://example.com/own.jpg' },
    });
    const wrapper = mount(ProfilePhotoAvatar, {
      props: { name: 'Owner', ownProfile: true, inboxId: 27 },
      global: { plugins: [store] },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(WhatsappProfileAPI.photo).toHaveBeenCalledWith(27);
    expect(WhatsappProfileAPI.contactPhoto).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('reports failures and lets the agent retry', async () => {
    WhatsappProfileAPI.contactPhoto
      .mockRejectedValueOnce(new Error('Disconnected'))
      .mockResolvedValueOnce({
        data: { photo_url: 'https://example.com/full.jpg' },
      });
    const wrapper = mount(ProfilePhotoAvatar, {
      props: {
        src: 'thumbnail.jpg',
        name: 'Contact',
        contactId: 10,
        inboxId: 27,
      },
      global: { plugins: [store] },
    });
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(wrapper.getComponent(ProfilePhotoViewer).props('error')).toBe(true);
    wrapper.getComponent(ProfilePhotoViewer).vm.$emit('retry');
    await flushPromises();
    expect(wrapper.getComponent(ProfilePhotoViewer).props('error')).toBe(false);
    expect(wrapper.getComponent(ProfilePhotoViewer).props('src')).toContain(
      'full.jpg'
    );
    wrapper.unmount();
  });

  it('ignores a request that finishes after the viewer has closed', async () => {
    let complete;
    WhatsappProfileAPI.contactPhoto.mockReturnValue(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    const wrapper = mount(ProfilePhotoAvatar, {
      props: {
        src: 'thumbnail.jpg',
        name: 'Contact',
        contactId: 10,
        inboxId: 27,
      },
      global: { plugins: [store] },
    });
    await wrapper.get('button').trigger('click');
    wrapper.getComponent(ProfilePhotoViewer).vm.$emit('close');
    complete({ data: { photo_url: 'stale.jpg' } });
    await flushPromises();
    expect(wrapper.findComponent(ProfilePhotoViewer).exists()).toBe(false);
    wrapper.unmount();
  });
});

describe('Photo crop', () => {
  it('adjusts zoom and resets without submitting the photo, then saves only on confirmation', async () => {
    vi.stubGlobal('URL', {
      createObjectURL: vi.fn().mockReturnValue('blob:photo'),
      revokeObjectURL: vi.fn(),
    });
    vi.stubGlobal(
      'Image',
      class {
        naturalWidth = 960;

        naturalHeight = 640;

        set src(value) {
          this.onload();
        }
      }
    );
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
      clearRect: vi.fn(),
      drawImage: vi.fn(),
      save: vi.fn(),
      beginPath: vi.fn(),
      rect: vi.fn(),
      arc: vi.fn(),
      fill: vi.fn(),
      restore: vi.fn(),
      fillRect: vi.fn(),
    });
    vi.spyOn(HTMLCanvasElement.prototype, 'toDataURL').mockReturnValue(
      'data:image/jpeg;base64,cropped'
    );
    const wrapper = mount(ProfilePhotoEditor, {
      props: { file: new Blob(['image']) },
      attachTo: document.body,
      global: { plugins: [store], stubs: { teleport: true } },
    });
    await flushPromises();
    wrapper.get('[aria-label="WHATSAPP_PROFILE.ZOOM_IN"]').element.click();
    await flushPromises();
    expect(wrapper.text()).toContain('WHATSAPP_PROFILE.ZOOM_PERCENT');
    expect(wrapper.emitted('confirm')).toBeUndefined();
    wrapper
      .findAll('button')
      .find(button => button.text() === 'WHATSAPP_PROFILE.RESET_CROP')
      .element.click();
    await flushPromises();
    expect(wrapper.emitted('confirm')).toBeUndefined();
    wrapper.get('button[type="submit"]').element.click();
    await flushPromises();
    expect(wrapper.emitted('confirm')).toEqual([['cropped']]);
    wrapper.unmount();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:photo');
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('keeps portrait and landscape crops fully covered at both drag limits', () => {
    expect(
      clampCrop({ width: 800, height: 1200, zoom: 1, x: -100, y: 2000 })
    ).toEqual({ side: 800, x: 400, y: 800 });
    expect(
      clampCrop({ width: 1200, height: 800, zoom: 2, x: 2000, y: -100 })
    ).toEqual({ side: 400, x: 1000, y: 200 });
  });

  it('exports the selected square without the circular preview mask', () => {
    const drawImage = vi.fn();
    const fillRect = vi.fn();
    const context = { drawImage, fillRect };
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(
      context
    );
    vi.spyOn(HTMLCanvasElement.prototype, 'toDataURL').mockReturnValue(
      'data:image/jpeg;base64,jpeg'
    );
    const image = { width: 1200, height: 800 };
    const crop = clampCrop({
      width: 1200,
      height: 800,
      zoom: 2,
      x: 750,
      y: 450,
    });
    expect(cropToJpeg(image, crop)).toBe('jpeg');
    expect(drawImage).toHaveBeenCalledWith(
      image,
      550,
      250,
      400,
      400,
      0,
      0,
      640,
      640
    );
    vi.restoreAllMocks();
  });
});

describe('Camera lifecycle', () => {
  it('captures the camera into an image and releases the stream', async () => {
    const stop = vi.fn();
    const photo = new Blob(['photo'], { type: 'image/jpeg' });
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: vi
          .fn()
          .mockResolvedValue({ getTracks: () => [{ stop }] }),
      },
    });
    vi.spyOn(HTMLMediaElement.prototype, 'play').mockResolvedValue();
    const drawImage = vi.fn();
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue({
      drawImage,
    });
    vi.spyOn(HTMLCanvasElement.prototype, 'toBlob').mockImplementation(
      callback => callback(photo)
    );
    const wrapper = mount(ProfileCamera, {
      attachTo: document.body,
      global: { plugins: [store], stubs: { teleport: true } },
    });
    await flushPromises();
    const video = wrapper.get('video');
    Object.defineProperty(video.element, 'videoWidth', { value: 1280 });
    Object.defineProperty(video.element, 'videoHeight', { value: 720 });
    await video.trigger('loadeddata');
    wrapper.get('button[type="submit"]').element.click();
    await flushPromises();
    expect(drawImage).toHaveBeenCalledWith(video.element, 0, 0);
    expect(wrapper.emitted('capture')).toEqual([[photo]]);
    expect(stop).toHaveBeenCalledOnce();
    wrapper.unmount();
    vi.restoreAllMocks();
  });

  it('shows a useful error when camera permission is denied', async () => {
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: vi.fn().mockRejectedValue(new Error('NotAllowedError')),
      },
    });
    const wrapper = mount(ProfileCamera, {
      global: { plugins: [store], stubs: { teleport: true } },
    });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'WHATSAPP_PROFILE.CAMERA_ERROR'
    );
    expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledWith(
      expect.objectContaining({ audio: false })
    );
    wrapper.unmount();
  });

  it('releases the camera immediately if the preview cannot start', async () => {
    const stop = vi.fn();
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: vi
          .fn()
          .mockResolvedValue({ getTracks: () => [{ stop }] }),
      },
    });
    vi.spyOn(HTMLMediaElement.prototype, 'play').mockRejectedValue(
      new Error('Playback failed')
    );
    const wrapper = mount(ProfileCamera, {
      global: { plugins: [store], stubs: { teleport: true } },
    });
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(stop).toHaveBeenCalledOnce();
    wrapper.unmount();
    vi.restoreAllMocks();
  });

  it('stops a delayed camera stream even if the dialog was closed before permission completed', async () => {
    let grant;
    const stop = vi.fn();
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: vi.fn().mockReturnValue(
          new Promise(resolve => {
            grant = resolve;
          })
        ),
      },
    });
    const wrapper = mount(ProfileCamera, { global: { plugins: [store] } });
    wrapper.unmount();
    grant({ getTracks: () => [{ stop }] });
    await flushPromises();
    expect(stop).toHaveBeenCalledOnce();
  });
});
