<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import WhatsmeowStickersAPI from 'dashboard/api/whatsmeowStickers';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { stickerPreviewUrl } from 'dashboard/helper/whatsmeowStickerHelper';

const props = defineProps({
  isOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'select']);
const { t } = useI18n();

const stickers = ref([]);
const isLoading = ref(false);
const failedStickerIds = ref(new Set());

const hasStickers = computed(() => stickers.value.length > 0);
const stickerUrl = sticker => stickerPreviewUrl(sticker);
const isAvailable = sticker =>
  sticker?.available !== false &&
  stickerUrl(sticker) &&
  !failedStickerIds.value.has(sticker.id);

const markFailed = sticker => {
  failedStickerIds.value = new Set([...failedStickerIds.value, sticker.id]);
};

const markLoaded = sticker => {
  const next = new Set(failedStickerIds.value);
  next.delete(sticker.id);
  failedStickerIds.value = next;
};

const loadStickers = async () => {
  isLoading.value = true;
  try {
    const { data } = await WhatsmeowStickersAPI.get();
    stickers.value = data.payload || [];
    failedStickerIds.value = new Set();
  } catch {
    useAlert(t('WHATSAPP_STATUS.VIEWER.LOAD_STICKERS_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

watch(
  () => props.isOpen,
  isOpen => {
    if (isOpen) loadStickers();
  }
);
</script>

<template>
  <div class="contents">
    <div
      v-if="isOpen"
      v-on-clickaway="() => emit('close')"
      class="absolute bottom-14 left-0 z-40 flex max-h-72 w-72 max-w-[calc(100vw-2rem)] flex-col overflow-hidden rounded-xl border border-white/15 bg-black/95 shadow-2xl backdrop-blur-xl"
      role="dialog"
      :aria-label="t('WHATSAPP_STATUS.VIEWER.STICKERS')"
    >
      <div
        class="flex items-center justify-between border-b border-white/10 px-3 py-2"
      >
        <p class="mb-0 text-xs font-semibold text-white">
          {{ t('WHATSAPP_STATUS.VIEWER.STICKERS') }}
        </p>
        <button
          type="button"
          class="flex size-8 items-center justify-center rounded-lg text-white/75 transition-colors hover:bg-white/10 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
          :aria-label="t('WHATSAPP_STATUS.VIEWER.CLOSE_STICKERS')"
          @click="emit('close')"
        >
          <Icon icon="i-lucide-x" class="size-4" />
        </button>
      </div>

      <div class="min-h-32 overflow-y-auto p-2">
        <div
          v-if="isLoading && !hasStickers"
          class="flex h-32 items-center justify-center"
        >
          <Spinner :size="22" class="text-white" />
        </div>
        <div
          v-else-if="!hasStickers"
          class="flex h-32 flex-col items-center justify-center gap-2 px-4 text-center text-xs text-white/70"
        >
          <Icon icon="i-lucide-sticker" class="size-6" />
          {{ t('WHATSAPP_STATUS.VIEWER.NO_STICKERS') }}
        </div>
        <div v-else class="grid grid-cols-4 gap-1.5">
          <button
            v-for="sticker in stickers"
            :key="sticker.id"
            type="button"
            class="grid aspect-square place-items-center rounded-lg p-1 transition-colors hover:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white disabled:cursor-not-allowed disabled:opacity-40"
            :disabled="!isAvailable(sticker)"
            :aria-label="t('WHATSAPP_STATUS.VIEWER.SEND_STICKER')"
            @click="emit('select', sticker)"
          >
            <img
              v-if="isAvailable(sticker)"
              :src="stickerUrl(sticker)"
              alt=""
              class="max-h-14 max-w-14 object-contain"
              loading="lazy"
              @load="markLoaded(sticker)"
              @error="markFailed(sticker)"
            />
            <Icon
              v-else
              icon="i-lucide-circle-off"
              class="size-5 text-white/40"
            />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
