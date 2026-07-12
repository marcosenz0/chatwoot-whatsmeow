<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useStatusTime } from './useStatusTime';

defineProps({
  groups: {
    type: Array,
    default: () => [],
  },
  deletingKeys: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['openPublication', 'deletePublication']);

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

const firstStatus = group => group.items[0] || {};
const backgroundClass = group =>
  BACKGROUND_CLASSES[firstStatus(group).metadata?.background] ||
  BACKGROUND_CLASSES.teal;
const viewerCount = group =>
  group.items.reduce(
    (total, status) => total + Number(status.viewer_count || 0),
    0
  );
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
          class="group/preview relative flex aspect-[16/9] w-full items-center justify-center overflow-hidden text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
          :class="backgroundClass(group)"
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
          <p
            v-else
            class="mb-0 line-clamp-3 px-6 text-center text-lg font-semibold leading-7 text-white"
          >
            {{ statusLabel(group) }}
          </p>
          <span
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
              <p class="mb-0 mt-1 text-xs text-n-slate-10">
                {{ formatStatusTime(group.latestAt) }}
              </p>
            </div>
            <span
              class="flex flex-shrink-0 items-center gap-1 rounded-full bg-n-alpha-2 px-2.5 py-1 text-xs text-n-slate-11"
            >
              <Icon icon="i-lucide-eye" class="size-3.5" />
              {{ viewerCount(group) }}
            </span>
          </div>

          <div class="flex flex-wrap gap-1.5">
            <span
              v-for="status in group.items"
              :key="status.id"
              class="max-w-full truncate rounded-md border border-n-weak bg-n-alpha-1 px-2 py-1 text-[0.6875rem] font-medium text-n-slate-11"
            >
              {{ status.inbox_name }}
            </span>
          </div>

          <div class="flex gap-2 border-t border-n-weak pt-3">
            <Button
              variant="faded"
              color="slate"
              icon="i-lucide-external-link"
              :label="t('WHATSAPP_STATUS.OWN_MANAGER.OPEN')"
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
              :disabled="deletingKeys.includes(group.key)"
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
