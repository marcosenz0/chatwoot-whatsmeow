<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';

import WhatsmeowStatusesAPI from 'dashboard/api/whatsmeowStatuses';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StatusComposer from './StatusComposer.vue';
import StatusInboxSelector from './StatusInboxSelector.vue';
import StatusInboxSettingsMenu from './StatusInboxSettingsMenu.vue';
import StatusViewer from './StatusViewer.vue';
import { useStatusTime } from './useStatusTime';

const POLL_INTERVAL = 30000;
const WHATSMEOW_CHANNEL_TYPE = 'Channel::Whatsmeow';
const ALL_INBOXES = 'all';

const { t } = useI18n();
const { formatStatusTime } = useStatusTime();
const { isAdmin } = useAdmin();
const route = useRoute();
const router = useRouter();
const store = useStore();

const inboxes = useMapGetter('inboxes/getInboxes');
const currentUser = useMapGetter('getCurrentUser');

const selectedInboxId = ref(null);
const statuses = ref([]);
const isInitializing = ref(true);
const isLoading = ref(false);
const hasLoadError = ref(false);
const composerRef = ref(null);
const isViewerOpen = ref(false);
const viewerGroupIndex = ref(0);
const viewerStatusIndex = ref(0);
const updatingStatusInboxIds = ref([]);
const isInboxSelectorOpen = ref(false);

let pollTimer = null;
let requestToken = 0;

const whatsmeowInboxes = computed(() =>
  inboxes.value.filter(inbox => inbox.channel_type === WHATSMEOW_CHANNEL_TYPE)
);

const selectedInbox = computed(() =>
  whatsmeowInboxes.value.find(
    inbox => String(inbox.id) === String(selectedInboxId.value)
  )
);

const hasSpecificInbox = computed(() => selectedInboxId.value !== ALL_INBOXES);

const targetInboxes = computed(() => {
  if (!hasSpecificInbox.value) return whatsmeowInboxes.value;
  return selectedInbox.value ? [selectedInbox.value] : [];
});

const isInboxConnected = inbox =>
  (inbox?.channel?.status || inbox?.status) === 'connected';

const selectedInboxLabel = computed(() =>
  hasSpecificInbox.value
    ? selectedInbox.value?.name || ''
    : t('WHATSAPP_STATUS.ALL_INBOXES')
);

const ignoredInboxes = computed(() =>
  targetInboxes.value.filter(inbox => inbox.ignore_status)
);

const ignoredStatusTitle = computed(() =>
  hasSpecificInbox.value
    ? t('WHATSAPP_STATUS.IGNORE_STATUS_TITLE')
    : t('WHATSAPP_STATUS.IGNORE_STATUS_ALL_TITLE', {
        count: ignoredInboxes.value.length,
      })
);

const ignoredStatusDescription = computed(() =>
  hasSpecificInbox.value
    ? t('WHATSAPP_STATUS.IGNORE_STATUS_DESCRIPTION')
    : t('WHATSAPP_STATUS.IGNORE_STATUS_ALL_DESCRIPTION')
);

const defaultComposerInboxIds = computed(() => {
  const publishableInboxes = hasSpecificInbox.value
    ? targetInboxes.value
    : whatsmeowInboxes.value;
  return publishableInboxes.filter(isInboxConnected).map(inbox => inbox.id);
});

const activeStatuses = computed(() => {
  const now = Date.now();
  return statuses.value.filter(status => status.expires_at * 1000 > now);
});

const groupKeyForStatus = status => {
  if (status.from_me) return 'current-user';
  const inboxPrefix = `inbox:${status.inbox_id}:`;
  if (status.contact?.id) return `${inboxPrefix}contact:${status.contact.id}`;
  if (status.sender_phone) return `${inboxPrefix}phone:${status.sender_phone}`;
  return `${inboxPrefix}jid:${status.sender_jid || status.id}`;
};

const statusGroups = computed(() => {
  const grouped = new Map();
  const orderedStatuses = activeStatuses.value
    .slice()
    .sort((a, b) => a.posted_at - b.posted_at);

  orderedStatuses.forEach(status => {
    const key = groupKeyForStatus(status);

    if (!grouped.has(key)) {
      const isOwnStatus = Boolean(status.from_me);
      grouped.set(key, {
        key,
        fromMe: isOwnStatus,
        name: isOwnStatus
          ? t('WHATSAPP_STATUS.MY_STATUS')
          : status.contact?.name ||
            status.sender_name ||
            status.sender_phone ||
            status.sender_jid,
        avatar: isOwnStatus
          ? currentUser.value.avatar_url
          : status.contact?.avatar_url ||
            status.metadata?.profile_picture_url ||
            '',
        items: [],
      });
    }

    grouped.get(key).items.push(status);
  });

  return Array.from(grouped.values()).map(group => {
    const inboxNames = Array.from(
      new Set(group.items.map(item => item.inbox_name).filter(Boolean))
    );

    return {
      ...group,
      inboxName:
        inboxNames.length === 1
          ? inboxNames[0]
          : t('WHATSAPP_STATUS.INBOX_COUNT', { count: inboxNames.length }),
      latestAt: group.items[group.items.length - 1].posted_at,
      viewed: group.items.every(status => status.viewed || status.from_me),
    };
  });
});

const ownGroup = computed(() => statusGroups.value.find(group => group.fromMe));

const incomingGroups = computed(() =>
  statusGroups.value
    .filter(group => !group.fromMe)
    .sort((a, b) => b.latestAt - a.latestAt)
);

const recentGroups = computed(() =>
  incomingGroups.value.filter(group => !group.viewed)
);

const viewedGroups = computed(() =>
  incomingGroups.value.filter(group => group.viewed)
);

const viewerGroups = computed(() => [
  ...(ownGroup.value ? [ownGroup.value] : []),
  ...incomingGroups.value,
]);

const ownStatusSubtitle = computed(() => {
  if (ownGroup.value) {
    return t('WHATSAPP_STATUS.INBOX_TIME', {
      inbox: ownGroup.value.inboxName,
      time: formatStatusTime(ownGroup.value.latestAt),
    });
  }
  return isAdmin.value
    ? t('WHATSAPP_STATUS.MY_STATUS_EMPTY')
    : t('WHATSAPP_STATUS.ADMIN_ONLY');
});

const initializeSelectedInbox = () => {
  const queryValue = String(route.query.inbox_id || ALL_INBOXES);
  if (queryValue === ALL_INBOXES) {
    selectedInboxId.value = ALL_INBOXES;
    return;
  }

  const queryInboxId = Number(queryValue);
  const requestedInbox = whatsmeowInboxes.value.find(
    inbox => inbox.id === queryInboxId
  );
  selectedInboxId.value = requestedInbox
    ? String(requestedInbox.id)
    : ALL_INBOXES;
};

const syncInboxQuery = inboxId => {
  if (!inboxId || String(route.query.inbox_id) === String(inboxId)) return;

  router.replace({
    query: {
      ...route.query,
      inbox_id: String(inboxId),
    },
  });
};

const fetchStatuses = async ({ silent = false } = {}) => {
  const selectedValue = String(selectedInboxId.value);
  const inboxesToFetch = targetInboxes.value.slice();
  if (!inboxesToFetch.length) return;

  requestToken += 1;
  const token = requestToken;
  if (!silent) isLoading.value = true;

  try {
    const results = await Promise.allSettled(
      inboxesToFetch.map(async inbox => {
        const { data } = await WhatsmeowStatusesAPI.getAll(inbox.id);
        return (data.payload || []).map(status => ({
          ...status,
          inbox_name: inbox.name,
        }));
      })
    );
    if (
      token !== requestToken ||
      selectedValue !== String(selectedInboxId.value)
    ) {
      return;
    }

    const fulfilledResults = results.filter(
      result => result.status === 'fulfilled'
    );
    statuses.value = fulfilledResults.flatMap(result => result.value);
    hasLoadError.value = fulfilledResults.length === 0;
  } catch {
    if (token === requestToken && (!silent || !statuses.value.length)) {
      hasLoadError.value = true;
    }
  } finally {
    if (token === requestToken) isLoading.value = false;
  }
};

const stopPolling = () => {
  if (!pollTimer) return;
  window.clearInterval(pollTimer);
  pollTimer = null;
};

const startPolling = () => {
  stopPolling();
  if (isViewerOpen.value || !selectedInboxId.value) return;

  pollTimer = window.setInterval(() => {
    if (document.visibilityState === 'visible') fetchStatuses({ silent: true });
  }, POLL_INTERVAL);
};

const openComposer = () => {
  if (isAdmin.value) {
    composerRef.value?.open(defaultComposerInboxIds.value);
  }
};

const openStatusGroup = groupKey => {
  const index = viewerGroups.value.findIndex(group => group.key === groupKey);
  if (index < 0) return;

  const firstUnseenIndex = viewerGroups.value[index].items.findIndex(
    status => !status.viewed && !status.from_me
  );
  viewerGroupIndex.value = index;
  viewerStatusIndex.value = firstUnseenIndex >= 0 ? firstUnseenIndex : 0;
  isViewerOpen.value = true;
};

const openOwnStatus = () => {
  if (ownGroup.value) openStatusGroup(ownGroup.value.key);
  else if (isAdmin.value) openComposer();
};

const onPublished = publishedStatuses => {
  publishedStatuses.forEach(status => {
    const inbox = whatsmeowInboxes.value.find(
      item => item.id === status.inbox_id
    );
    const decoratedStatus = { ...status, inbox_name: inbox?.name || '' };
    const existingIndex = statuses.value.findIndex(
      item => item.id === status.id
    );
    if (existingIndex >= 0) {
      statuses.value.splice(existingIndex, 1, decoratedStatus);
    } else {
      statuses.value.push(decoratedStatus);
    }
  });
};

const onViewed = statusId => {
  statuses.value = statuses.value.map(status =>
    status.id === statusId ? { ...status, viewed: true } : status
  );
};

const setInboxUpdating = (inboxId, isUpdating) => {
  const ids = new Set(updatingStatusInboxIds.value);
  if (isUpdating) ids.add(inboxId);
  else ids.delete(inboxId);
  updatingStatusInboxIds.value = Array.from(ids);
};

const updateStatusEnabled = async ({ inbox, enabled }) => {
  if (!inbox || updatingStatusInboxIds.value.includes(inbox.id)) return;

  setInboxUpdating(inbox.id, true);
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: inbox.id,
      formData: false,
      channel: { ignore_status: !enabled },
    });
    const message = enabled
      ? t('WHATSAPP_STATUS.STATUS_ENABLED', { inbox: inbox.name })
      : t('WHATSAPP_STATUS.STATUS_DISABLED', { inbox: inbox.name });
    useAlert(message);
    if (enabled) fetchStatuses({ silent: true });
  } catch {
    useAlert(t('WHATSAPP_STATUS.STATUS_UPDATE_ERROR'));
  } finally {
    setInboxUpdating(inbox.id, false);
  }
};

watch(
  whatsmeowInboxes,
  availableInboxes => {
    if (selectedInboxId.value === ALL_INBOXES) return;
    const selectedStillExists = availableInboxes.some(
      inbox => String(inbox.id) === String(selectedInboxId.value)
    );
    if (!selectedStillExists) initializeSelectedInbox();
  },
  { deep: true }
);

watch(selectedInboxId, inboxId => {
  requestToken += 1;
  statuses.value = [];
  hasLoadError.value = false;
  syncInboxQuery(inboxId);
  fetchStatuses();
  startPolling();
});

watch(isViewerOpen, isOpen => {
  if (isOpen) stopPolling();
  else startPolling();
});

onMounted(async () => {
  if (!inboxes.value.length) await store.dispatch('inboxes/get');
  initializeSelectedInbox();
  isInitializing.value = false;
  startPolling();
});

onBeforeUnmount(() => {
  requestToken += 1;
  stopPolling();
});
</script>

<template>
  <div class="flex h-full min-h-0 w-full bg-n-background">
    <div
      v-if="isInitializing"
      class="flex h-full w-full items-center justify-center text-n-slate-11"
      role="status"
    >
      <Spinner :size="28" />
      <span class="sr-only">{{ t('WHATSAPP_STATUS.LOADING') }}</span>
    </div>

    <div
      v-else-if="!whatsmeowInboxes.length"
      class="flex h-full w-full flex-col items-center justify-center gap-3 px-6 text-center"
    >
      <span
        class="flex size-16 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-10"
      >
        <Icon icon="i-lucide-circle-dashed" class="size-8" />
      </span>
      <h1 class="mb-0 text-lg font-semibold text-n-slate-12">
        {{ t('WHATSAPP_STATUS.NO_INBOX_TITLE') }}
      </h1>
      <p class="mb-0 max-w-md text-sm leading-6 text-n-slate-11">
        {{ t('WHATSAPP_STATUS.NO_INBOX_DESCRIPTION') }}
      </p>
    </div>

    <template v-else>
      <section
        class="flex h-full min-h-0 w-full flex-col border-n-weak bg-n-solid-1 md:max-w-[26rem] md:border-r"
        :aria-label="t('WHATSAPP_STATUS.TITLE')"
      >
        <header class="border-b border-n-weak px-5 pb-4 pt-5">
          <div class="flex items-center justify-between gap-3">
            <h1 class="mb-0 text-xl font-semibold text-n-slate-12">
              {{ t('WHATSAPP_STATUS.TITLE') }}
            </h1>
            <div class="flex items-center gap-1">
              <StatusInboxSettingsMenu
                v-if="isAdmin"
                :inboxes="targetInboxes"
                :updating-inbox-ids="updatingStatusInboxIds"
                @toggle="updateStatusEnabled"
              />
              <Button
                v-if="isAdmin"
                icon="i-lucide-plus"
                color="slate"
                variant="ghost"
                size="lg"
                :aria-label="t('WHATSAPP_STATUS.ADD_STATUS')"
                @click="openComposer"
              />
            </div>
          </div>

          <span
            class="mt-4 block text-xs font-medium uppercase tracking-wide text-n-slate-10"
          >
            {{ t('WHATSAPP_STATUS.SELECT_INBOX') }}
          </span>
          <StatusInboxSelector
            v-model="selectedInboxId"
            :inboxes="whatsmeowInboxes"
            class="mt-2"
            @open-change="isInboxSelectorOpen = $event"
          />

          <div
            v-if="ignoredInboxes.length"
            class="mt-3 flex gap-3 rounded-lg bg-n-amber-3 px-3 py-3 text-n-amber-11"
            role="status"
          >
            <Icon
              icon="i-lucide-triangle-alert"
              class="mt-0.5 size-4 flex-shrink-0"
            />
            <div class="min-w-0">
              <p class="mb-0 text-xs font-semibold">
                {{ ignoredStatusTitle }}
              </p>
              <p class="mb-0 mt-1 text-xs leading-5">
                {{ ignoredStatusDescription }}
              </p>
            </div>
          </div>
        </header>

        <div
          class="min-h-0 flex-1 px-3 py-3"
          :class="isInboxSelectorOpen ? 'overflow-y-hidden' : 'overflow-y-auto'"
        >
          <div
            class="group flex min-h-[4.75rem] w-full items-center gap-3 rounded-xl px-3 transition-colors"
            :class="{ 'hover:bg-n-alpha-2': ownGroup || isAdmin }"
          >
            <span class="relative flex-shrink-0">
              <button
                type="button"
                class="rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
                :aria-label="t('WHATSAPP_STATUS.MY_STATUS')"
                :disabled="!ownGroup && !isAdmin"
                @click="openOwnStatus"
              >
                <span
                  class="flex rounded-full border-2 p-0.5"
                  :class="
                    ownGroup
                      ? 'border-n-teal-9'
                      : 'border-n-slate-5 border-dashed'
                  "
                >
                  <Avatar
                    :name="currentUser.name || t('WHATSAPP_STATUS.MY_STATUS')"
                    :src="currentUser.avatar_url"
                    :size="50"
                    rounded-full
                  />
                </span>
              </button>
            </span>
            <button
              type="button"
              class="min-h-[4.75rem] min-w-0 flex-1 text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
              :disabled="!ownGroup && !isAdmin"
              @click="openOwnStatus"
            >
              <span
                class="block truncate text-sm font-semibold text-n-slate-12"
              >
                {{ t('WHATSAPP_STATUS.MY_STATUS') }}
              </span>
              <span class="mt-1 block truncate text-xs text-n-slate-11">
                {{ ownStatusSubtitle }}
              </span>
            </button>
            <button
              v-if="isAdmin"
              type="button"
              class="flex size-9 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-brand transition-colors hover:bg-n-alpha-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
              :aria-label="t('WHATSAPP_STATUS.ADD_STATUS')"
              :title="t('WHATSAPP_STATUS.ADD_STATUS')"
              @click="openComposer"
            >
              <Icon icon="i-lucide-plus" class="size-5" />
            </button>
          </div>

          <div class="mb-2 mt-5 flex items-center justify-between px-3">
            <h2
              class="mb-0 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
            >
              {{ t('WHATSAPP_STATUS.RECENT') }}
            </h2>
            <Spinner v-if="isLoading && statuses.length" :size="16" />
          </div>

          <div
            v-if="isLoading && !statuses.length"
            class="flex flex-col gap-2 px-1"
            role="status"
          >
            <div
              v-for="index in 4"
              :key="index"
              class="flex min-h-[4.5rem] animate-pulse items-center gap-3 rounded-xl px-3 motion-reduce:animate-none"
            >
              <span class="size-12 rounded-full bg-n-alpha-2" />
              <span class="flex flex-1 flex-col gap-2">
                <span class="h-3 w-2/3 rounded bg-n-alpha-2" />
                <span class="h-2.5 w-1/3 rounded bg-n-alpha-2" />
              </span>
            </div>
            <span class="sr-only">{{ t('WHATSAPP_STATUS.LOADING') }}</span>
          </div>

          <div
            v-else-if="hasLoadError"
            class="mx-2 flex flex-col items-center gap-3 rounded-xl border border-n-weak bg-n-alpha-2 px-5 py-8 text-center"
          >
            <Icon icon="i-lucide-wifi-off" class="size-6 text-n-slate-10" />
            <p class="mb-0 text-sm leading-6 text-n-slate-11">
              {{ t('WHATSAPP_STATUS.LOAD_ERROR') }}
            </p>
            <Button
              variant="faded"
              color="slate"
              icon="i-lucide-refresh-cw"
              :label="t('WHATSAPP_STATUS.RETRY')"
              @click="fetchStatuses()"
            />
          </div>

          <template v-else>
            <div v-if="recentGroups.length" class="flex flex-col gap-1">
              <button
                v-for="group in recentGroups"
                :key="group.key"
                type="button"
                class="flex min-h-[4.5rem] w-full items-center gap-3 rounded-xl px-3 text-left transition-colors hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                @click="openStatusGroup(group.key)"
              >
                <span
                  class="flex flex-shrink-0 rounded-full border-2 border-n-teal-9 p-0.5"
                >
                  <Avatar
                    :name="group.name"
                    :src="group.avatar"
                    :size="48"
                    rounded-full
                  />
                </span>
                <span class="min-w-0 flex-1">
                  <span
                    class="block truncate text-sm font-semibold text-n-slate-12"
                  >
                    {{ group.name }}
                  </span>
                  <span class="mt-1 block truncate text-xs text-n-slate-11">
                    {{
                      t('WHATSAPP_STATUS.INBOX_TIME', {
                        inbox: group.inboxName,
                        time: formatStatusTime(group.latestAt),
                      })
                    }}
                  </span>
                </span>
                <span
                  class="size-2 flex-shrink-0 rounded-full bg-n-teal-9"
                  aria-hidden="true"
                />
              </button>
            </div>

            <div
              v-else-if="!viewedGroups.length"
              class="mx-2 flex flex-col items-center px-4 py-10 text-center"
            >
              <span
                class="flex size-12 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-10"
              >
                <Icon icon="i-lucide-clock-3" class="size-5" />
              </span>
              <h2 class="mb-0 mt-4 text-sm font-semibold text-n-slate-12">
                {{ t('WHATSAPP_STATUS.NO_RECENT_TITLE') }}
              </h2>
              <p class="mb-0 mt-2 max-w-xs text-xs leading-5 text-n-slate-11">
                <template v-if="hasSpecificInbox">
                  {{ t('WHATSAPP_STATUS.NO_RECENT_DESCRIPTION') }}
                </template>
                <template v-else>
                  {{ t('WHATSAPP_STATUS.NO_RECENT_ALL_DESCRIPTION') }}
                </template>
              </p>
            </div>

            <div v-if="viewedGroups.length" class="mt-5">
              <div class="mb-2 flex items-center px-3">
                <h2
                  class="mb-0 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
                >
                  {{ t('WHATSAPP_STATUS.VIEWED') }}
                </h2>
              </div>

              <div class="flex flex-col gap-1">
                <button
                  v-for="group in viewedGroups"
                  :key="group.key"
                  type="button"
                  class="flex min-h-[4.5rem] w-full items-center gap-3 rounded-xl px-3 text-left transition-colors hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                  @click="openStatusGroup(group.key)"
                >
                  <span
                    class="flex flex-shrink-0 rounded-full border-2 border-n-slate-5 p-0.5"
                  >
                    <Avatar
                      :name="group.name"
                      :src="group.avatar"
                      :size="48"
                      rounded-full
                    />
                  </span>
                  <span class="min-w-0 flex-1">
                    <span
                      class="block truncate text-sm font-medium text-n-slate-12"
                    >
                      {{ group.name }}
                    </span>
                    <span class="mt-1 block truncate text-xs text-n-slate-11">
                      {{
                        t('WHATSAPP_STATUS.INBOX_TIME', {
                          inbox: group.inboxName,
                          time: formatStatusTime(group.latestAt),
                        })
                      }}
                    </span>
                  </span>
                </button>
              </div>
            </div>
          </template>
        </div>
      </section>

      <aside
        class="hidden min-w-0 flex-1 flex-col items-center justify-center bg-n-background px-10 text-center md:flex"
      >
        <span
          class="relative flex size-24 items-center justify-center rounded-full border border-n-weak text-n-slate-10"
        >
          <span class="absolute inset-3 rounded-full border border-n-weak" />
          <Icon icon="i-lucide-circle-dashed" class="size-10" />
        </span>
        <h2 class="mb-0 mt-7 text-2xl font-medium text-n-slate-12">
          {{ t('WHATSAPP_STATUS.EMPTY_PANEL_TITLE') }}
        </h2>
        <p class="mb-0 mt-3 max-w-lg text-sm leading-6 text-n-slate-11">
          {{ t('WHATSAPP_STATUS.EMPTY_PANEL_DESCRIPTION') }}
        </p>
        <p class="mb-0 mt-2 text-xs text-n-slate-10">
          {{ selectedInboxLabel }}
        </p>
      </aside>

      <StatusComposer
        v-if="isAdmin"
        ref="composerRef"
        :inboxes="whatsmeowInboxes"
        @published="onPublished"
      />

      <StatusViewer
        v-if="isViewerOpen && viewerGroups.length"
        :groups="viewerGroups"
        :initial-group-index="viewerGroupIndex"
        :initial-status-index="viewerStatusIndex"
        @close="isViewerOpen = false"
        @viewed="onViewed"
      />
    </template>
  </div>
</template>
