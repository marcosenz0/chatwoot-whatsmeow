<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store.js';

import WhatsmeowStatusesAPI from 'dashboard/api/whatsmeowStatuses';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import StatusViewer from 'dashboard/routes/dashboard/status/StatusViewer.vue';

const props = defineProps({
  statusReply: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');

const status = ref(null);
const isLoading = ref(false);
const isViewerOpen = ref(false);

const statusId = computed(() => Number(props.statusReply?.id));
const statusType = computed(() => status.value?.status_type || 'text');
const hasPreviewMedia = computed(
  () => statusType.value === 'image' && Boolean(status.value?.media?.url)
);
const videoThumbnailUrl = computed(() => {
  const metadata = status.value?.metadata || {};
  if (!metadata.thumbnail_base64) return '';

  return `data:${metadata.thumbnail_content_type || 'image/jpeg'};base64,${metadata.thumbnail_base64}`;
});
const previewImageUrl = computed(() => {
  if (hasPreviewMedia.value) return status.value.media.url;
  if (statusType.value === 'video') return videoThumbnailUrl.value;
  return '';
});
const statusIcon = computed(() => {
  if (statusType.value === 'video') return 'i-lucide-video';
  if (statusType.value === 'image') return 'i-lucide-image';
  return 'i-lucide-message-circle';
});
const previewText = computed(() => {
  if (status.value?.content) return status.value.content;
  if (statusType.value === 'video')
    return t('WHATSAPP_STATUS.REPLY_PREVIEW.VIDEO');
  if (statusType.value === 'image')
    return t('WHATSAPP_STATUS.REPLY_PREVIEW.IMAGE');
  return t('WHATSAPP_STATUS.REPLY_PREVIEW.TEXT');
});
const viewerGroups = computed(() => {
  if (!status.value) return [];

  return [
    {
      key: `whatsmeow-status-reply:${status.value.id}`,
      fromMe: true,
      name: t('WHATSAPP_STATUS.MY_STATUS'),
      avatar: currentUser.value?.avatar_url || '',
      inboxName: status.value.inbox_name || '',
      items: [status.value],
    },
  ];
});

const loadStatus = async () => {
  if (!statusId.value || isLoading.value) return null;

  isLoading.value = true;
  try {
    const { data } = await WhatsmeowStatusesAPI.preview(statusId.value);
    status.value = data.payload;
    return status.value;
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t('WHATSAPP_STATUS.REPLY_PREVIEW.UNAVAILABLE')
    );
    return null;
  } finally {
    isLoading.value = false;
  }
};

const openStatus = async () => {
  const loadedStatus = status.value || (await loadStatus());
  if (loadedStatus) isViewerOpen.value = true;
};

onMounted(loadStatus);
</script>

<template>
  <button
    type="button"
    data-status-interactive
    class="mb-2 flex w-full items-center gap-3 overflow-hidden rounded-lg bg-n-alpha-black1 p-2 text-left transition-colors hover:bg-n-alpha-black2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand disabled:cursor-wait"
    :aria-label="t('WHATSAPP_STATUS.REPLY_PREVIEW.OPEN')"
    :disabled="isLoading"
    @click="openStatus"
  >
    <span
      class="flex size-11 flex-shrink-0 items-center justify-center overflow-hidden rounded-md bg-n-alpha-2 text-n-slate-11"
    >
      <img
        v-if="previewImageUrl"
        :src="previewImageUrl"
        alt=""
        class="h-full w-full object-cover"
      />
      <Spinner v-else-if="isLoading" :size="18" />
      <Icon v-else :icon="statusIcon" class="size-5" />
    </span>
    <span class="min-w-0 flex-1">
      <span class="block text-xs font-semibold text-n-slate-12">
        {{ t('WHATSAPP_STATUS.REPLY_PREVIEW.TITLE') }}
      </span>
      <span class="mt-0.5 block line-clamp-2 text-xs leading-5 text-n-slate-11">
        {{ previewText }}
      </span>
    </span>
    <Icon
      icon="i-lucide-chevron-right"
      class="size-4 flex-shrink-0 text-n-slate-10"
    />
  </button>

  <StatusViewer
    v-if="isViewerOpen && viewerGroups.length"
    :groups="viewerGroups"
    @close="isViewerOpen = false"
  />
</template>
