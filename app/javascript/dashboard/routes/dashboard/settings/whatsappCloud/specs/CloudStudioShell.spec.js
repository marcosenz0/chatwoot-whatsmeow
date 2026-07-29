import { flushPromises, shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';

import CloudStudio from '../index.vue';
import OverviewPanel from '../OverviewPanel.vue';
import {
  whatsappCloudAutomationsAPI,
  whatsappCloudTemplatesAPI,
} from 'dashboard/api/whatsappCloudStudio';

const storeMock = vi.hoisted(() => ({
  dispatch: vi.fn(),
  refs: {},
}));

vi.mock('dashboard/api/whatsappCloudStudio', () => ({
  whatsappCloudTemplatesAPI: {
    getForInbox: vi.fn(),
    sync: vi.fn(),
  },
  whatsappCloudAutomationsAPI: {
    getForInbox: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  Object.assign(storeMock.refs, {
    inboxes: ref([]),
    campaigns: ref([]),
    labels: ref([]),
  });

  const getters = {
    'inboxes/getInboxes': storeMock.refs.inboxes,
    'campaigns/getWhatsAppCampaigns': storeMock.refs.campaigns,
    'labels/getLabels': storeMock.refs.labels,
  };

  return {
    useStore: () => ({ dispatch: storeMock.dispatch }),
    useMapGetter: key => getters[key],
  };
});

describe('WhatsApp Cloud Studio shell', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    storeMock.refs.inboxes.value = [];
    storeMock.refs.campaigns.value = [];
    storeMock.refs.labels.value = [];
    whatsappCloudTemplatesAPI.getForInbox.mockResolvedValue({
      data: { templates: [], last_updated_at: null },
    });
    whatsappCloudAutomationsAPI.getForInbox.mockResolvedValue({ data: [] });
  });

  it('selects an official inbox as soon as it arrives without waiting for the other stores', async () => {
    let resolveLabels;
    let resolveCampaigns;
    const labelsRequest = new Promise(resolve => {
      resolveLabels = resolve;
    });
    const campaignsRequest = new Promise(resolve => {
      resolveCampaigns = resolve;
    });
    const officialInbox = {
      id: 29,
      name: 'MarcosAPI',
      channel_type: 'Channel::Whatsapp',
      provider: 'whatsapp_cloud',
    };

    storeMock.dispatch.mockImplementation(action => {
      if (action === 'inboxes/get') {
        storeMock.refs.inboxes.value = [officialInbox];
        return Promise.resolve();
      }
      if (action === 'labels/get') return labelsRequest;
      if (action === 'campaigns/get') return campaignsRequest;
      return Promise.resolve();
    });

    const wrapper = shallowMount(CloudStudio);
    await nextTick();
    await flushPromises();

    expect(whatsappCloudTemplatesAPI.getForInbox).toHaveBeenCalledWith(29);
    expect(whatsappCloudAutomationsAPI.getForInbox).toHaveBeenCalledWith(29);
    expect(wrapper.getComponent(OverviewPanel).props('inbox')).toEqual(
      officialInbox
    );

    resolveLabels();
    resolveCampaigns();
    await flushPromises();
    wrapper.unmount();
  });
});
