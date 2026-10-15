import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/marcosxAi';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SavedResourceLibrary from '../SavedResourceLibrary.vue';
import ResourceVideoPlayer from '../ResourceVideoPlayer.vue';

vi.mock('dashboard/api/marcosxAi', () => ({
  default: { getResources: vi.fn(), saveResource: vi.fn() },
}));
const photo = {
  id: 11,
  title: 'Existing photo',
  kind: 'image',
  thumb_url: '/thumb.jpg',
  file_url: '/photo.jpg',
  enabled: true,
  audience: 'global',
  contact_ids: [],
};
const video = {
  id: 12,
  title: 'Existing video',
  kind: 'video',
  file_url: '/clip.mp4',
  enabled: true,
  audience: 'contacts',
  contact_ids: [21],
};
const options = {
  props: { agentId: 3, conversationId: 92 },
  attachTo: document.body,
  global: {
    stubs: {
      ContextMenu: { template: '<div tabindex="0"><slot /></div>' },
      Dialog: {
        setup(_, { expose }) {
          expose({ open: vi.fn(), close: vi.fn() });
        },
        template: '<div><slot /></div>',
      },
    },
  },
};
beforeEach(() => {
  vi.clearAllMocks();
  API.getResources.mockResolvedValue({
    data: { resources: [photo, video], total: 2, per_page: 24 },
  });
  API.saveResource.mockResolvedValue({
    data: {
      resource: {
        ...photo,
        audience: 'conversation',
        conversation_id: 92,
        contact_ids: [],
      },
    },
  });
});
afterEach(() => {
  document.body.innerHTML = '';
});

it('previews saved images and videos without selecting, uploading or changing them', async () => {
  const wrapper = mount(SavedResourceLibrary, options);
  await flushPromises();
  const tiles = wrapper.findAll('[data-testid="saved-resource"]');
  expect(tiles).toHaveLength(2);
  expect(wrapper.find('input[type="file"]').exists()).toBe(false);
  await tiles[0].trigger('click');
  expect(wrapper.findComponent(Dialog).find('img').attributes('src')).toBe(
    '/photo.jpg'
  );
  await tiles[1].trigger('click');
  expect(wrapper.findComponent(ResourceVideoPlayer).props('src')).toBe(
    '/clip.mp4'
  );
  wrapper.findComponent(Dialog).vm.$emit('close');
  await flushPromises();
  expect(wrapper.findComponent(ResourceVideoPlayer).exists()).toBe(false);
  expect(API.saveResource).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('changes only the right-clicked item to this conversation and updates its icon', async () => {
  const wrapper = mount(SavedResourceLibrary, options);
  await flushPromises();
  await wrapper
    .findAll('[data-testid="saved-resource"]')[0]
    .trigger('contextmenu', { clientX: 200, clientY: 150 });
  const choices = wrapper.findAll('[role="menuitemradio"]');
  expect(choices[0].attributes('aria-checked')).toBe('true');
  await choices[1].trigger('click');
  await flushPromises();
  expect(API.saveResource).toHaveBeenCalledWith(3, 11, {
    resource: {
      audience: 'conversation',
      conversation_id: 92,
      contact_ids: [],
    },
  });
  expect(wrapper.emitted('updated')).toHaveLength(1);
  expect(
    wrapper
      .findAll('[data-testid="saved-resource"]')[0]
      .find('[title*="BADGE_CONVERSATION"]')
      .exists()
  ).toBe(true);
  expect(
    wrapper
      .findAll('[data-testid="saved-resource"]')[1]
      .find('[title*="BADGE_CONTACTS"]')
      .exists()
  ).toBe(true);
  wrapper.unmount();
});

it('can promote a contact-restricted item to global without retaining old recipients', async () => {
  API.saveResource.mockResolvedValue({
    data: { resource: { ...video, audience: 'global', contact_ids: [] } },
  });
  const wrapper = mount(SavedResourceLibrary, options);
  await flushPromises();
  await wrapper
    .findAll('[data-testid="saved-resource"]')[1]
    .trigger('contextmenu');
  await wrapper.findAll('[role="menuitemradio"]')[0].trigger('click');
  await flushPromises();
  expect(API.saveResource).toHaveBeenCalledWith(3, 12, {
    resource: { audience: 'global', conversation_id: null, contact_ids: [] },
  });
  wrapper.unmount();
});

it('keeps the saved audience and reports a failed update', async () => {
  API.saveResource.mockRejectedValue(new Error('offline'));
  const wrapper = mount(SavedResourceLibrary, options);
  await flushPromises();
  await wrapper
    .findAll('[data-testid="saved-resource"]')[0]
    .trigger('contextmenu');
  await wrapper.findAll('[role="menuitemradio"]')[1].trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toContain('RESOURCES.ERROR');
  expect(
    wrapper
      .findAll('[data-testid="saved-resource"]')[0]
      .find('[title*="BADGE_GLOBAL"]')
      .exists()
  ).toBe(true);
  expect(wrapper.emitted('updated')).toBeUndefined();
  wrapper.unmount();
});

it('supports keyboard context menus and Escape without dismissing the file editor', async () => {
  const wrapper = mount(SavedResourceLibrary, options);
  await flushPromises();
  const tile = wrapper.findAll('[data-testid="saved-resource"]')[0];
  await tile.trigger('keydown', { key: 'F10', shiftKey: true });
  const menuRoot = wrapper.get('div[tabindex="0"]');
  await menuRoot.trigger('keydown', { key: 'ArrowDown' });
  expect(document.activeElement).toBe(
    wrapper.findAll('[role="menuitemradio"]')[0].element
  );
  await menuRoot.trigger('keydown', { key: 'Escape' });
  await flushPromises();
  expect(wrapper.find('[role="menu"]').exists()).toBe(false);
  expect(document.activeElement).toBe(tile.element);
  expect(API.saveResource).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('paginates the saved library independently and does not mark a different conversation as selected', async () => {
  API.getResources
    .mockResolvedValueOnce({
      data: {
        resources: [
          { ...photo, audience: 'conversation', conversation_id: 91 },
        ],
        total: 25,
        per_page: 24,
      },
    })
    .mockResolvedValueOnce({
      data: { resources: [video], total: 25, per_page: 24 },
    });
  const wrapper = mount(SavedResourceLibrary, options);
  await flushPromises();
  await wrapper.get('[data-testid="saved-resource"]').trigger('contextmenu');
  expect(
    wrapper.findAll('[role="menuitemradio"]')[1].attributes('aria-checked')
  ).toBe('false');
  await wrapper.get('[role="menu"]').trigger('keydown', { key: 'Escape' });
  await wrapper
    .get('button[aria-label="MARCOX_AI.WORKSPACE.NEXT"]')
    .trigger('click');
  await flushPromises();
  expect(API.getResources).toHaveBeenLastCalledWith(3, { search: '', page: 2 });
  expect(
    wrapper.get('[data-testid="saved-resource"]').attributes('title')
  ).toBe('Existing video');
  wrapper.unmount();
});
