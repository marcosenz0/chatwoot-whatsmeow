<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
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
    count: campaigns.value.length,
  },
]);

const loadInboxData = async () => {
  if (!selectedInboxId.value) return;
  isLoading.value = true;
  try {
    const [templatesResponse, automationsResponse] = await Promise.all([
      whatsappCloudTemplatesAPI.getForInbox(selectedInboxId.value),
      whatsappCloudAutomationsAPI.getForInbox(selectedInboxId.value),
    ]);
    templates.value = templatesResponse.data.templates || [];
    templatesLastUpdatedAt.value = templatesResponse.data.last_updated_at;
    automations.value = automationsResponse.data || [];
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('WHATSAPP_CLOUD_STUDIO.API.LOAD_ERROR')
    );
  } finally {
    isLoading.value = false;
  }
};

const refreshAll = async () => {
  if (!selectedInboxId.value) return;
  isRefreshing.value = true;
  try {
    const response = await whatsappCloudTemplatesAPI.sync(
      selectedInboxId.value
    );
    templates.value = response.data.templates || [];
    templatesLastUpdatedAt.value = response.data.last_updated_at;
    await loadInboxData();
    await store.dispatch('campaigns/get');
    useAlert(t('WHATSAPP_CLOUD_STUDIO.API.REFRESHED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('WHATSAPP_CLOUD_STUDIO.API.LOAD_ERROR')
    );
  } finally {
    isRefreshing.value = false;
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

watch(selectedInboxId, loadInboxData);

onMounted(async () => {
  await Promise.all([
    store.dispatch('inboxes/get'),
    store.dispatch('labels/get'),
    store.dispatch('campaigns/get'),
  ]);
  selectedInboxId.value = officialInboxes.value[0]?.id || null;
});
</script>

<template>
  <section class="flex h-full w-full flex-col overflow-hidden bg-n-surface-1">
    <header class="border-b border-n-weak bg-n-surface-1 px-6 py-5">
      <div
        class="mx-auto flex w-full max-w-[90rem] flex-wrap items-start justify-between gap-4"
      >
        <div>
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
        <div class="flex min-w-64 items-end gap-2">
          <label
            class="flex min-w-56 flex-1 flex-col gap-1 text-xs font-medium text-n-slate-11"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.INBOX_LABEL') }}
            <select
              v-model="selectedInboxId"
              class="h-10 rounded-lg border border-n-strong bg-n-alpha-2 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            >
              <option
                v-for="inbox in officialInboxes"
                :key="inbox.id"
                :value="inbox.id"
              >
                {{ inbox.name }}
              </option>
            </select>
          </label>
          <Button
            :label="t('WHATSAPP_CLOUD_STUDIO.REFRESH')"
            icon="i-lucide-refresh-cw"
            color="slate"
            variant="outline"
            :is-loading="isRefreshing"
            :disabled="!selectedInboxId"
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

    <template v-else>
      <nav
        class="border-b border-n-weak bg-n-surface-1 px-6"
        :aria-label="t('WHATSAPP_CLOUD_STUDIO.TABS.ARIA_LABEL')"
      >
        <div class="mx-auto flex w-full max-w-[90rem] gap-1 overflow-x-auto">
          <button
            v-for="tab in tabs"
            :key="tab.id"
            type="button"
            class="flex min-h-11 items-center gap-2 border-b-2 px-4 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
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

      <main class="flex-1 overflow-auto px-6 py-6">
        <div v-if="isLoading" class="flex h-60 items-center justify-center">
          <Spinner />
        </div>
        <div v-else class="mx-auto w-full max-w-[90rem]">
          <OverviewPanel
            v-if="activeTab === 'overview'"
            :inbox="selectedInbox"
            :templates="templates"
            :automations="automations"
            :campaigns="campaigns"
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
            :campaigns="campaigns"
          />
        </div>
      </main>
    </template>
  </section>
</template>
