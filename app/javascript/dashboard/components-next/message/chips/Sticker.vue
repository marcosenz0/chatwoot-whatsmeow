<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsmeowStickersAPI from 'dashboard/api/whatsmeowStickers';
import Icon from 'next/icon/Icon.vue';
import Button from 'next/button/Button.vue';
import { useMessageContext } from '../provider.js';
import {
  stickerAttachmentId,
  stickerDataUrl,
} from 'dashboard/helper/whatsmeowStickerHelper';

const props = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
});

const { sender } = useMessageContext();
const { t } = useI18n();

const thumbnailHasError = ref(false);
const previewHasError = ref(false);
const showPreview = ref(false);
const isLoadingFavorite = ref(false);
const favorite = ref(null);

const sourceUrl = computed(
  () =>
    stickerDataUrl(props.attachment) ||
    props.attachment?.thumbUrl ||
    props.attachment?.thumb_url ||
    ''
);
const senderName = computed(
  () => sender.value?.name || t('CONVERSATION.WHATSMEOW_STICKER.UNKNOWN_SENDER')
);
const favoriteLabel = computed(() =>
  favorite.value
    ? t('CONVERSATION.WHATSMEOW_STICKER.REMOVE_FAVORITE')
    : t('CONVERSATION.WHATSMEOW_STICKER.ADD_FAVORITE')
);
const canOpenPreview = computed(
  () => !!sourceUrl.value && !thumbnailHasError.value
);

const openPreview = () => {
  if (canOpenPreview.value) showPreview.value = true;
};

const handleThumbnailError = () => {
  thumbnailHasError.value = true;
};

const handlePreviewError = () => {
  previewHasError.value = true;
};

const findFavorite = async () => {
  isLoadingFavorite.value = true;
  try {
    const { data } = await WhatsmeowStickersAPI.get();
    const attachmentId = props.attachment.id;
    favorite.value = (data.payload || []).find(
      item => stickerAttachmentId(item) === attachmentId
    );
  } catch (error) {
    useAlert(t('CONVERSATION.WHATSMEOW_STICKER.LOAD_FAILED'));
  } finally {
    isLoadingFavorite.value = false;
  }
};

const toggleFavorite = async () => {
  isLoadingFavorite.value = true;
  try {
    if (favorite.value) {
      await WhatsmeowStickersAPI.delete(favorite.value.id);
      favorite.value = null;
      useAlert(t('CONVERSATION.WHATSMEOW_STICKER.REMOVED'));
    } else {
      const { data } = await WhatsmeowStickersAPI.save(props.attachment.id);
      favorite.value = data.payload;
      useAlert(t('CONVERSATION.WHATSMEOW_STICKER.ADDED'));
    }
  } catch (error) {
    useAlert(t('CONVERSATION.WHATSMEOW_STICKER.SAVE_FAILED'));
  } finally {
    isLoadingFavorite.value = false;
  }
};

watch(showPreview, value => {
  if (value) {
    previewHasError.value = false;
    findFavorite();
  }
});

watch(sourceUrl, () => {
  thumbnailHasError.value = false;
  previewHasError.value = false;
});
</script>

<template>
  <button
    type="button"
    data-whatsmeow-sticker-context="true"
    class="group relative grid size-28 shrink-0 place-items-center overflow-hidden rounded-xl bg-transparent p-1 enabled:hover:bg-n-alpha-1 disabled:cursor-default"
    :disabled="!canOpenPreview"
    @click="openPreview"
  >
    <span
      v-if="thumbnailHasError || !sourceUrl"
      class="flex size-full flex-col items-center justify-center gap-1 rounded-lg bg-n-alpha-1 p-2 text-center text-xs text-n-slate-11"
    >
      <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
      {{ $t('COMPONENTS.MEDIA.LOADING_FAILED') }}
    </span>
    <img
      v-else
      class="max-h-28 max-w-28 object-contain"
      :src="sourceUrl"
      :alt="$t('CONVERSATION.WHATSMEOW_STICKER.PREVIEW_TITLE')"
      @error="handleThumbnailError"
    />
  </button>

  <Teleport to="body">
    <div
      v-if="showPreview"
      class="fixed inset-0 z-[9999] flex flex-col bg-slate-900 text-white"
      @click="showPreview = false"
    >
      <div class="flex items-center justify-between px-6 py-5" @click.stop>
        <div class="flex min-w-0 items-center gap-3">
          <div
            class="grid size-10 shrink-0 place-items-center rounded-full bg-white/10 font-semibold text-white"
          >
            {{ senderName.slice(0, 1).toUpperCase() }}
          </div>
          <div class="min-w-0">
            <p class="mb-0 truncate text-sm font-semibold">{{ senderName }}</p>
            <p class="mb-0 text-xs text-white/60">
              {{ $t('CONVERSATION.WHATSMEOW_STICKER.PREVIEW_TITLE') }}
            </p>
          </div>
        </div>
        <button
          type="button"
          class="grid size-9 place-items-center rounded-lg bg-white/10 text-white hover:bg-white/15"
          :aria-label="$t('GENERAL.CLOSE')"
          @click="showPreview = false"
        >
          <Icon icon="i-lucide-x" class="size-5" />
        </button>
      </div>

      <div
        class="flex min-h-0 flex-1 flex-col items-center justify-center px-6"
      >
        <img
          v-if="sourceUrl && !previewHasError"
          class="max-h-[62vh] max-w-[min(28rem,80vw)] object-contain"
          :src="sourceUrl"
          :alt="$t('CONVERSATION.WHATSMEOW_STICKER.PREVIEW_TITLE')"
          @click.stop
          @error="handlePreviewError"
        />
        <div
          v-else
          class="flex flex-col items-center gap-2 rounded-xl bg-white/10 p-6 text-white/70"
          @click.stop
        >
          <Icon icon="i-lucide-circle-off" class="size-6" />
          {{ $t('COMPONENTS.MEDIA.LOADING_FAILED') }}
        </div>
        <Button
          class="mt-8"
          :label="favoriteLabel"
          :icon="favorite ? 'i-lucide-star-off' : 'i-lucide-star'"
          :is-loading="isLoadingFavorite"
          :disabled="isLoadingFavorite"
          slate
          faded
          @click.stop="toggleFavorite"
        />
      </div>
    </div>
  </Teleport>
</template>
