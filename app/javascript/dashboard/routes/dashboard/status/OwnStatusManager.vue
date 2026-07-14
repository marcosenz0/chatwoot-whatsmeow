<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useStatusTime } from './useStatusTime';

const props = defineProps({
  groups: {
    type: Array,
    default: () => [],
  },
  deletingKeys: {
    type: Array,
    default: () => [],
  },
  retryingKeys: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits([
  'openPublication',
  'deletePublication',
  'retryPublication',
]);

const { t } = useI18n();
const { formatStatusTime } = useStatusTime();

const dialogRef = ref(null);
const pendingDeleteKey = ref('');

const BACKGROUND_CLASSES = {
  teal: 'bg-n-teal-9',
  blue: 'bg-n-blue-9',
  violet: 'bg-n-violet-9',
  amber: 'bg-n-amber-9',
  ruby: 'bg-n-ruby-9',
  slate: 'bg-n-slate-11',
};

const STATE_VISUALS = {
  queued: {
    icon: 'i-lucide-clock-3',
    class: 'border-n-amber-6 bg-n-amber-3 text-n-amber-11',
    iconClass: 'text-n-amber-11',
  },
  processing: {
    icon: 'i-lucide-loader-circle',
    class: 'border-n-blue-6 bg-n-blue-3 text-n-blue-11',
    iconClass: 'text-n-blue-11',
  },
  published: {
    icon: 'i-lucide-circle-check',
    class: 'border-n-teal-6 bg-n-teal-3 text-n-teal-11',
    iconClass: 'text-n-teal-11',
  },
  failed: {
    icon: 'i-lucide-circle-alert',
    class: 'border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11',
    iconClass: 'text-n-ruby-11',
  },
};

const firstStatus = group => group.items[0] || {};
const isDeleting = status => status.publication_state === 'deleting';
const isDeleteFailed = status => status.publication_state === 'delete_failed';
const publicationState = status => {
  const state = status.publication_state || 'published';
  if (isDeleting(status)) return 'processing';
  if (isDeleteFailed(status)) return 'failed';
  return STATE_VISUALS[state] ? state : 'published';
};
const publicationStateLabel = status => {
  if (isDeleting(status)) {
    return t('WHATSAPP_STATUS.OWN_MANAGER.STATE_DELETING');
  }
  if (isDeleteFailed(status)) {
    return t('WHATSAPP_STATUS.OWN_MANAGER.STATE_DELETE_FAILED');
  }

  const state = publicationState(status);
  if (state === 'queued') {
    return t('WHATSAPP_STATUS.OWN_MANAGER.STATE_QUEUED');
  }
  if (state === 'processing') {
    return t('WHATSAPP_STATUS.OWN_MANAGER.STATE_PROCESSING');
  }
  if (state === 'failed') {
    return t('WHATSAPP_STATUS.OWN_MANAGER.STATE_FAILED');
  }
  return t('WHATSAPP_STATUS.OWN_MANAGER.STATE_PUBLISHED');
};
const publicationStateVisual = status =>
  STATE_VISUALS[publicationState(status)];
const publicationOverallState = group => {
  const states = group.items.map(publicationState);
  if (states.includes('processing')) return 'processing';
  if (states.includes('failed')) return 'failed';
  if (states.includes('queued')) return 'queued';
  return 'published';
};
const publicationOverallStatus = group => {
  if (group.items.some(isDeleting)) return { publication_state: 'deleting' };
  if (group.items.some(isDeleteFailed)) {
    return { publication_state: 'delete_failed' };
  }

  return { publication_state: publicationOverallState(group) };
};
const orderedStatuses = group =>
  group.items
    .slice()
    .sort(
      (first, second) =>
        Number(first.publication_position || 0) -
        Number(second.publication_position || 0)
    );
const canOpenPublication = group =>
  group.items.some(status => publicationState(status) === 'published');
const retryKey = status =>
  `${status.publication_id || status.id}:${status.session_key || status.inbox_id}`;
const isRetrying = status => props.retryingKeys.includes(retryKey(status));
const backgroundClass = group =>
  BACKGROUND_CLASSES[firstStatus(group).metadata?.background] ||
  BACKGROUND_CLASSES.teal;
const viewerCount = group => {
  const countsBySession = new Map();
  group.items.forEach(status => {
    const key = status.session_key || `inbox:${status.inbox_id}`;
    const count = Number(status.viewer_count || 0);
    countsBySession.set(key, Math.max(countsBySession.get(key) || 0, count));
  });
  return Array.from(countsBySession.values()).reduce(
    (total, count) => total + count,
    0
  );
};
const mediaLabel = status => {
  if (status.status_type === 'image') {
    return t('WHATSAPP_STATUS.OWN_MANAGER.IMAGE');
  }
  if (status.status_type === 'video') {
    return t('WHATSAPP_STATUS.OWN_MANAGER.VIDEO');
  }
  if (status.status_type === 'audio') {
    return t('WHATSAPP_STATUS.OWN_MANAGER.AUDIO');
  }
  return t('WHATSAPP_STATUS.OWN_MANAGER.STATUS');
};
const statusLabel = group => {
  const status = firstStatus(group);
  return status.content || mediaLabel(status);
};

const open = () => {
  pendingDeleteKey.value = '';
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const openPublication = group => {
  if (!canOpenPublication(group)) return;

  close();
  emit('openPublication', group.key);
};

const requestDelete = group => {
  if (pendingDeleteKey.value !== group.key) {
    pendingDeleteKey.value = group.key;
    return;
  }

  emit('deletePublication', group.key);
  pendingDeleteKey.value = '';
};

const retryPublication = status => emit('retryPublication', status);

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :title="t('WHATSAPP_STATUS.OWN_MANAGER.TITLE')"
    :description="t('WHATSAPP_STATUS.OWN_MANAGER.DESCRIPTION')"
    :show-confirm-button="false"
    :cancel-button-label="t('WHATSAPP_STATUS.OWN_MANAGER.CLOSE')"
  >
    <div
      v-if="groups.length"
      class="grid max-h-[65dvh] grid-cols-1 gap-3 overflow-y-auto pr-1 sm:grid-cols-2"
    >
      <article
        v-for="group in groups"
        :key="group.key"
        class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
      >
        <button
          type="button"
          class="group/preview relative flex aspect-[16/9] w-full items-center justify-center overflow-hidden text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand disabled:cursor-default"
          :class="backgroundClass(group)"
          :disabled="!canOpenPublication(group)"
          @click="openPublication(group)"
        >
          <img
            v-if="
              firstStatus(group).status_type === 'image' &&
              firstStatus(group).media?.url
            "
            :src="firstStatus(group).media.url"
            :alt="statusLabel(group)"
            class="h-full w-full object-cover transition-transform duration-300 group-hover/preview:scale-[1.02] motion-reduce:transition-none"
          />
          <video
            v-else-if="
              firstStatus(group).status_type === 'video' &&
              firstStatus(group).media?.url
            "
            :src="firstStatus(group).media.url"
            muted
            preload="metadata"
            class="h-full w-full object-cover"
          />
          <span
            v-else-if="firstStatus(group).status_type === 'audio'"
            class="flex flex-col items-center gap-3 text-white"
          >
            <span
              class="flex size-14 items-center justify-center rounded-full bg-white/15"
            >
              <Icon icon="i-lucide-mic-2" class="size-6" />
            </span>
            <span class="text-sm font-semibold">{{ statusLabel(group) }}</span>
          </span>
          <p
            v-else
            class="mb-0 line-clamp-3 px-6 text-center text-lg font-semibold leading-7 text-white"
          >
            {{ statusLabel(group) }}
          </p>

          <span
            class="absolute left-3 top-3 flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium shadow-sm"
            :class="
              publicationStateVisual(publicationOverallStatus(group)).class
            "
          >
            <Icon
              :icon="
                publicationStateVisual(publicationOverallStatus(group)).icon
              "
              class="size-3.5"
              :class="{
                'animate-spin motion-reduce:animate-none':
                  publicationOverallState(group) === 'processing',
              }"
            />
            {{ publicationStateLabel(publicationOverallStatus(group)) }}
          </span>

          <span
            v-if="canOpenPublication(group)"
            class="absolute bottom-3 right-3 flex size-9 items-center justify-center rounded-full bg-n-black/60 text-white backdrop-blur-sm"
          >
            <Icon icon="i-lucide-play" class="size-4" />
          </span>
        </button>

        <div class="flex flex-col gap-3 p-4">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="mb-0 truncate text-sm font-semibold text-n-slate-12">
                {{ statusLabel(group) }}
              </p>
              <p
                v-if="group.latestAt"
                class="mb-0 mt-1 text-xs text-n-slate-10"
              >
                {{ formatStatusTime(group.latestAt) }}
              </p>
            </div>
            <span
              v-if="canOpenPublication(group)"
              class="flex flex-shrink-0 items-center gap-1 rounded-full bg-n-alpha-2 px-2.5 py-1 text-xs text-n-slate-11"
            >
              <Icon icon="i-lucide-eye" class="size-3.5" />
              {{ viewerCount(group) }}
            </span>
          </div>

          <div class="flex flex-col gap-1.5">
            <div
              v-for="status in orderedStatuses(group)"
              :key="status.id"
              class="flex min-w-0 items-start gap-2 rounded-lg border border-n-weak bg-n-alpha-1 px-2.5 py-2"
            >
              <Icon
                :icon="publicationStateVisual(status).icon"
                class="mt-0.5 size-4 flex-shrink-0"
                :class="[
                  publicationStateVisual(status).iconClass,
                  {
                    'animate-spin rounded-full motion-reduce:animate-none':
                      publicationState(status) === 'processing',
                  },
                ]"
              />
              <div class="min-w-0 flex-1">
                <div class="flex min-w-0 items-center justify-between gap-2">
                  <span
                    class="min-w-0 truncate text-xs font-medium text-n-slate-12"
                  >
                    {{ status.inbox_name }}
                  </span>
                  <span
                    class="flex-shrink-0 text-[0.6875rem] font-medium"
                    :class="publicationStateVisual(status).iconClass"
                  >
                    {{ publicationStateLabel(status) }}
                  </span>
                </div>
                <p
                  v-if="publicationState(status) === 'failed'"
                  class="mb-0 mt-1 line-clamp-2 text-[0.6875rem] leading-4 text-n-ruby-11"
                >
                  <template v-if="isDeleteFailed(status)">
                    {{ t('WHATSAPP_STATUS.OWN_MANAGER.DELETE_FAILURE_DETAIL') }}
                  </template>
                  <template v-else>
                    {{ t('WHATSAPP_STATUS.OWN_MANAGER.FAILURE_DETAIL') }}
                  </template>
                </p>
                <button
                  v-if="publicationState(status) === 'failed'"
                  type="button"
                  class="mt-1.5 flex min-h-7 items-center gap-1.5 rounded-md px-2 text-xs font-medium text-n-brand transition-colors hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="isRetrying(status)"
                  @click="retryPublication(status)"
                >
                  <Icon
                    :icon="
                      isRetrying(status)
                        ? 'i-lucide-loader-circle'
                        : 'i-lucide-refresh-cw'
                    "
                    class="size-3.5"
                    :class="{
                      'animate-spin motion-reduce:animate-none':
                        isRetrying(status),
                    }"
                  />
                  {{ t('WHATSAPP_STATUS.OWN_MANAGER.RETRY') }}
                </button>
              </div>
            </div>
          </div>

          <div class="flex gap-2 border-t border-n-weak pt-3">
            <Button
              variant="faded"
              color="slate"
              icon="i-lucide-external-link"
              :label="t('WHATSAPP_STATUS.OWN_MANAGER.OPEN')"
              :disabled="!canOpenPublication(group)"
              class="min-w-0 flex-1"
              @click="openPublication(group)"
            />
            <Button
              variant="faded"
              color="ruby"
              :icon="
                pendingDeleteKey === group.key
                  ? 'i-lucide-triangle-alert'
                  : 'i-lucide-trash-2'
              "
              :label="
                pendingDeleteKey === group.key
                  ? t('WHATSAPP_STATUS.OWN_MANAGER.CONFIRM_DELETE')
                  : t('WHATSAPP_STATUS.OWN_MANAGER.DELETE')
              "
              :is-loading="deletingKeys.includes(group.key)"
              :disabled="
                deletingKeys.includes(group.key) ||
                publicationOverallState(group) === 'processing'
              "
              @click="requestDelete(group)"
            />
          </div>
        </div>
      </article>
    </div>

    <div
      v-else
      class="flex min-h-64 flex-col items-center justify-center rounded-2xl border border-dashed border-n-weak px-6 text-center"
    >
      <span
        class="flex size-12 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-10"
      >
        <Icon icon="i-lucide-clock-3" class="size-5" />
      </span>
      <p class="mb-0 mt-4 text-sm font-semibold text-n-slate-12">
        {{ t('WHATSAPP_STATUS.OWN_MANAGER.EMPTY_TITLE') }}
      </p>
      <p class="mb-0 mt-2 max-w-sm text-xs leading-5 text-n-slate-10">
        {{ t('WHATSAPP_STATUS.OWN_MANAGER.EMPTY_DESCRIPTION') }}
      </p>
    </div>
  </Dialog>
</template>
