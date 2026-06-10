<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsmeowStickersAPI from 'dashboard/api/whatsmeowStickers';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import { stickerDataUrl } from 'dashboard/helper/whatsmeowStickerHelper';

const props = defineProps({
  isOpen: {
    type: Boolean,
    default: false,
  },
  conversationId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['close', 'sent']);
const { t } = useI18n();

const stickers = ref([]);
const isLoading = ref(false);
const sendingStickerId = ref(null);

const hasStickers = computed(() => stickers.value.length > 0);

const loadStickers = async () => {
  isLoading.value = true;
  try {
    const { data } = await WhatsmeowStickersAPI.get();
    stickers.value = data.payload || [];
  } catch (error) {
    useAlert(t('CONVERSATION.WHATSMEOW_STICKER.LOAD_FAILED'));
  } finally {
    isLoading.value = false;
  }
};

const sendSticker = async sticker => {
  sendingStickerId.value = sticker.id;
  try {
    const { data } = await WhatsmeowStickersAPI.send(
      sticker.id,
      props.conversationId
    );
    emit('sent', data.payload);
  } catch (error) {
    useAlert(t('CONVERSATION.WHATSMEOW_STICKER.SEND_FAILED'));
  } finally {
    sendingStickerId.value = null;
  }
};

watch(
  () => props.isOpen,
  value => {
    if (value) loadStickers();
  }
);
</script>

<template>
  <div class="contents">
    <div
      v-if="isOpen"
      v-on-clickaway="() => emit('close')"
      class="absolute bottom-16 left-3 z-[80] flex max-h-[30rem] w-[29rem] max-w-[calc(100vw-2rem)] flex-col rounded-xl border border-n-weak bg-n-solid-2 shadow-xl"
    >
      <div
        class="flex items-center justify-between border-b border-n-weak px-3 py-2"
      >
        <div class="min-w-0">
          <p class="mb-0 text-sm font-semibold text-n-slate-12">
            {{ $t('CONVERSATION.WHATSMEOW_STICKER.PICKER_TITLE') }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ $t('CONVERSATION.WHATSMEOW_STICKER.PICKER_SUBTITLE') }}
          </p>
        </div>
        <div class="flex items-center gap-1">
          <NextButton
            v-tooltip.top="$t('CONVERSATION.WHATSMEOW_STICKER.REFRESH')"
            icon="i-lucide-refresh-cw"
            slate
            faded
            xs
            :is-loading="isLoading"
            @click="loadStickers"
          />
          <NextButton icon="i-lucide-x" slate faded xs @click="emit('close')" />
        </div>
      </div>

      <div class="min-h-[14rem] overflow-y-auto p-3">
        <div
          v-if="isLoading && !hasStickers"
          class="flex h-48 items-center justify-center text-sm text-n-slate-11"
        >
          {{ $t('CONVERSATION.WHATSMEOW_STICKER.LOADING') }}
        </div>
        <div
          v-else-if="!hasStickers"
          class="flex h-48 flex-col items-center justify-center gap-2 text-center text-sm text-n-slate-11"
        >
          <Icon icon="i-lucide-sticker" class="size-8" />
          <p class="mb-0 font-medium text-n-slate-12">
            {{ $t('CONVERSATION.WHATSMEOW_STICKER.NO_STICKERS') }}
          </p>
          <p class="mb-0 max-w-56 text-xs">
            {{ $t('CONVERSATION.WHATSMEOW_STICKER.NO_STICKERS_HINT') }}
          </p>
        </div>
        <div v-else class="grid grid-cols-4 gap-2">
          <button
            v-for="sticker in stickers"
            :key="sticker.id"
            type="button"
            class="grid aspect-square place-items-center rounded-xl border border-transparent p-1 hover:border-n-weak hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="!!sendingStickerId"
            @click="sendSticker(sticker)"
          >
            <Icon
              v-if="sendingStickerId === sticker.id"
              icon="i-lucide-loader-circle"
              class="size-5 animate-spin text-n-slate-11"
            />
            <img
              v-else
              class="max-h-20 max-w-20 object-contain skip-context-menu"
              :src="stickerDataUrl(sticker)"
              :alt="$t('CONVERSATION.WHATSMEOW_STICKER.PREVIEW_TITLE')"
            />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
