<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StudioSelect from './StudioSelect.vue';
import OverviewPanel from './OverviewPanel.vue';
import TemplatesPanel from './TemplatesPanel.vue';
import FlowsPanel from './FlowsPanel.vue';
import BroadcastsPanel from './BroadcastsPanel.vue';
import {
  whatsappCloudAutomationsAPI,
  whatsappCloudTemplatesAPI,
} from 'dashboard/api/whatsappCloudStudio';

const { t } = useI18n();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const campaigns = useMapGetter('campaigns/getWhatsAppCampaigns');
const labels = useMapGetter('labels/getLabels');

const selectedInboxId = ref(null);
const activeTab = ref('overview');
const templates = ref([]);
const automations = ref([]);
const templatesLastUpdatedAt = ref(null);
const isLoading = ref(false);
const isRefreshing = ref(false);
let inboxLoadRequest = 0;
let refreshRequest = 0;

const officialInboxes = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === 'Channel::Whatsapp' &&
      inbox.provider === 'whatsapp_cloud'
  )
);

const selectedInbox = computed(() =>
  officialInboxes.value.find(
    inbox => inbox.id === Number(selectedInboxId.value)
  )
);

const officialCampaigns = computed(() =>
  campaigns.value.filter(
    campaign => campaign.inbox?.id === Number(selectedInboxId.value)
  )
);

const tabs = computed(() => [
  {
    id: 'overview',
    label: t('WHATSAPP_CLOUD_STUDIO.TABS.OVERVIEW'),
    icon: 'i-lucide-layout-dashboard',
  },
  {
    id: 'flows',
    label: t('WHATSAPP_CLOUD_STUDIO.TABS.FLOWS'),
    icon: 'i-lucide-workflow',
    count: automations.value.length,
  },
  {
    id: 'templates',
    label: t('WHATSAPP_CLOUD_STUDIO.TABS.TEMPLATES'),
    icon: 'i-lucide-panels-top-left',
    count: templates.value.length,
  },
  {
    id: 'broadcasts',
    label: t('WHATSAPP_CLOUD_STUDIO.TABS.BROADCASTS'),
    icon: 'i-lucide-send',
    count: officialCampaigns.value.length,
  },
]);

const isCurrentInbox = inboxId =>
  Number(selectedInboxId.value) === Number(inboxId);

const loadInboxData = async inboxId => {
  if (!inboxId) return false;
  inboxLoadRequest += 1;
  const requestId = inboxLoadRequest;
  isLoading.value = true;
  try {
    const [templatesResponse, automationsResponse] = await Promise.all([
      whatsappCloudTemplatesAPI.getForInbox(inboxId),
      whatsappCloudAutomationsAPI.getForInbox(inboxId),
    ]);
    if (requestId !== inboxLoadRequest || !isCurrentInbox(inboxId)) {
      return false;
    }
    templates.value = templatesResponse.data.templates || [];
    templatesLastUpdatedAt.value = templatesResponse.data.last_updated_at;
    automations.value = automationsResponse.data || [];
    return true;
  } catch (error) {
    if (requestId === inboxLoadRequest && isCurrentInbox(inboxId)) {
      useAlert(t('WHATSAPP_CLOUD_STUDIO.API.LOAD_ERROR'));
    }
    return false;
  } finally {
    if (requestId === inboxLoadRequest) {
      isLoading.value = false;
    }
  }
};

const refreshAll = async () => {
  if (!selectedInboxId.value) return;
  const inboxId = selectedInboxId.value;
  refreshRequest += 1;
  const requestId = refreshRequest;
  isRefreshing.value = true;
  try {
    const response = await whatsappCloudTemplatesAPI.sync(inboxId);
    if (requestId !== refreshRequest || !isCurrentInbox(inboxId)) return;
    templates.value = response.data.templates || [];
    templatesLastUpdatedAt.value = response.data.last_updated_at;
    const inboxLoaded = await loadInboxData(inboxId);
    if (!inboxLoaded || !isCurrentInbox(inboxId)) return;
    await store.dispatch('campaigns/get');
    if (requestId !== refreshRequest || !isCurrentInbox(inboxId)) return;
    useAlert(t('WHATSAPP_CLOUD_STUDIO.API.REFRESHED'));
  } catch {
    if (requestId === refreshRequest && isCurrentInbox(inboxId)) {
      useAlert(t('WHATSAPP_CLOUD_STUDIO.API.LOAD_ERROR'));
    }
  } finally {
    if (requestId === refreshRequest) {
      isRefreshing.value = false;
    }
  }
};

const updateTemplates = data => {
  templates.value = data.templates || [];
  templatesLastUpdatedAt.value =
    data.last_updated_at || templatesLastUpdatedAt.value;
};

const updateAutomations = records => {
  automations.value = records;
};

watch(selectedInboxId, inboxId => loadInboxData(inboxId));

watch(
  officialInboxes,
  inboxList => {
    const selectedInboxStillExists = inboxList.some(inbox =>
      isCurrentInbox(inbox.id)
    );
    if (!selectedInboxStillExists) {
      selectedInboxId.value = inboxList[0]?.id || null;
    }
  },
  { immediate: true }
);

onMounted(async () => {
  await Promise.all([
    store.dispatch('inboxes/get'),
    store.dispatch('labels/get'),
    store.dispatch('campaigns/get'),
  ]);
});
</script>

<template>
  <section
    class="flex h-full min-w-0 max-w-full flex-1 flex-col overflow-hidden bg-n-surface-1"
  >
    <header
      class="min-w-0 border-b border-n-weak bg-n-surface-1 px-4 py-5 sm:px-6"
    >
      <div
        class="mx-auto flex min-w-0 w-full max-w-[90rem] flex-col gap-5 xl:flex-row xl:items-end xl:justify-between"
      >
        <div class="min-w-0">
          <div class="mb-1 flex items-center gap-2 text-sm text-n-teal-11">
            <span class="i-logos-whatsapp-icon size-4" aria-hidden="true" />
            <span>{{ t('WHATSAPP_CLOUD_STUDIO.OFFICIAL_ONLY') }}</span>
          </div>
          <h1 class="text-2xl font-semibold text-n-slate-12">
            {{ t('WHATSAPP_CLOUD_STUDIO.TITLE') }}
          </h1>
          <p class="mt-1 max-w-3xl text-sm text-n-slate-11">
            {{ t('WHATSAPP_CLOUD_STUDIO.DESCRIPTION') }}
          </p>
        </div>
        <div
          class="grid w-full gap-2 sm:grid-cols-[minmax(14rem,20rem)_auto] sm:items-end xl:w-auto"
        >
          <label
            class="flex min-w-0 flex-col gap-1.5 text-xs font-medium text-n-slate-11"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.INBOX_LABEL') }}
            <StudioSelect
              v-model="selectedInboxId"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.INBOX_LABEL')"
            >
              <option
                v-for="inbox in officialInboxes"
                :key="inbox.id"
                :value="inbox.id"
              >
                {{ inbox.name }}
              </option>
            </StudioSelect>
          </label>
          <Button
            class="!h-11 w-full sm:w-auto"
            :label="t('WHATSAPP_CLOUD_STUDIO.REFRESH')"
            icon="i-lucide-refresh-cw"
            color="slate"
            variant="outline"
            :is-loading="isRefreshing"
            :disabled="!selectedInboxId || isRefreshing"
            @click="refreshAll"
          />
        </div>
      </div>
    </header>

    <div
      v-if="officialInboxes.length === 0"
      class="flex flex-1 items-center justify-center p-8"
    >
      <div
        class="max-w-lg rounded-2xl border border-n-weak bg-n-alpha-1 p-8 text-center"
      >
        <span
          class="i-lucide-message-circle-off mx-auto mb-4 block size-10 text-n-slate-10"
          aria-hidden="true"
        />
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{ t('WHATSAPP_CLOUD_STUDIO.EMPTY.TITLE') }}
        </h2>
        <p class="mt-2 text-sm text-n-slate-11">
          {{ t('WHATSAPP_CLOUD_STUDIO.EMPTY.DESCRIPTION') }}
        </p>
      </div>
    </div>

    <div
      v-else-if="!selectedInbox"
      class="flex flex-1 items-center justify-center p-8"
    >
      <Spinner />
    </div>

    <template v-else>
      <nav
        class="min-w-0 border-b border-n-weak bg-n-surface-1 px-4 sm:px-6"
        :aria-label="t('WHATSAPP_CLOUD_STUDIO.TABS.ARIA_LABEL')"
      >
        <div
          class="no-scrollbar mx-auto flex min-w-0 w-full max-w-[90rem] gap-1 overflow-x-auto"
        >
          <button
            v-for="tab in tabs"
            :key="tab.id"
            type="button"
            class="flex min-h-11 shrink-0 items-center gap-2 whitespace-nowrap border-b-2 px-4 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="
              activeTab === tab.id
                ? 'border-n-brand text-n-blue-11'
                : 'border-transparent text-n-slate-10 hover:text-n-slate-12'
            "
            @click="activeTab = tab.id"
          >
            <span class="size-4" :class="tab.icon" aria-hidden="true" />
            <span>{{ tab.label }}</span>
            <span
              v-if="tab.count"
              class="rounded-full bg-n-alpha-2 px-1.5 py-0.5 text-xs"
            >
              {{ tab.count }}
            </span>
          </button>
        </div>
      </nav>

      <main
        class="min-w-0 max-w-full flex-1 overflow-x-hidden overflow-y-auto px-4 py-5 sm:px-6 sm:py-6"
      >
        <div v-if="isLoading" class="flex h-60 items-center justify-center">
          <Spinner />
        </div>
        <div v-else class="mx-auto w-full max-w-[90rem]">
          <OverviewPanel
            v-if="activeTab === 'overview'"
            :inbox="selectedInbox"
            :templates="templates"
            :automations="automations"
            :campaigns="officialCampaigns"
            :templates-last-updated-at="templatesLastUpdatedAt"
            @open-tab="activeTab = $event"
          />
          <FlowsPanel
            v-else-if="activeTab === 'flows'"
            :inbox="selectedInbox"
            :templates="templates"
            :automations="automations"
            @update="updateAutomations"
          />
          <TemplatesPanel
            v-else-if="activeTab === 'templates'"
            :inbox="selectedInbox"
            :templates="templates"
            :last-updated-at="templatesLastUpdatedAt"
            @update="updateTemplates"
          />
          <BroadcastsPanel
            v-else
            :inbox="selectedInbox"
            :templates="templates"
            :labels="labels"
            :campaigns="officialCampaigns"
            :automations="automations"
          />
        </div>
      </main>
    </template>
  </section>
</template>
