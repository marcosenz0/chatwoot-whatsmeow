<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsmeowStickersAPI from 'dashboard/api/whatsmeowStickers';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import { stickerPreviewUrl } from 'dashboard/helper/whatsmeowStickerHelper';

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
const deletingStickerId = ref(null);
const failedStickerIds = ref(new Set());
const activeMenuStickerId = ref(null);
const openedConversationId = ref(null);

const hasStickers = computed(() => stickers.value.length > 0);
const activeConversationId = computed(() => Number(props.conversationId || 0));

const stickerImageUrl = sticker => stickerPreviewUrl(sticker);

const stickerHasFailed = sticker => failedStickerIds.value.has(sticker.id);

const stickerIsAvailable = sticker =>
  sticker?.available !== false &&
  !!stickerImageUrl(sticker) &&
  !stickerHasFailed(sticker);

const setStickerFailed = sticker => {
  failedStickerIds.value = new Set([...failedStickerIds.value, sticker.id]);
};

const clearStickerFailed = sticker => {
  const nextFailedIds = new Set(failedStickerIds.value);
  nextFailedIds.delete(sticker.id);
  failedStickerIds.value = nextFailedIds;
};

const loadStickers = async () => {
  isLoading.value = true;
  try {
    const { data } = await WhatsmeowStickersAPI.get();
    stickers.value = data.payload || [];
    failedStickerIds.value = new Set();
    activeMenuStickerId.value = null;
  } catch (error) {
    useAlert(t('CONVERSATION.WHATSMEOW_STICKER.LOAD_FAILED'));
  } finally {
    isLoading.value = false;
  }
};

const stickerSendErrorMessage = error => {
  if (error?.response?.status === 409) {
    return t('CONVERSATION.WHATSMEOW_STICKER.CONVERSATION_CHANGED');
  }

  if (error?.response?.status === 422) {
    return t('CONVERSATION.WHATSMEOW_STICKER.UNAVAILABLE');
  }

  return t('CONVERSATION.WHATSMEOW_STICKER.SEND_FAILED');
};

const sendSticker = async sticker => {
  const targetConversationId = activeConversationId.value;
  if (
    !targetConversationId ||
    openedConversationId.value !== targetConversationId
  ) {
    emit('close');
    useAlert(t('CONVERSATION.WHATSMEOW_STICKER.CONVERSATION_CHANGED'));
    return;
  }

  if (!stickerIsAvailable(sticker)) {
    useAlert(t('CONVERSATION.WHATSMEOW_STICKER.UNAVAILABLE'));
    return;
  }

  activeMenuStickerId.value = null;
  sendingStickerId.value = sticker.id;
  try {
    const { data } = await WhatsmeowStickersAPI.send(
      sticker.id,
      targetConversationId,
      openedConversationId.value
    );
    emit('sent', data.payload);
  } catch (error) {
    useAlert(stickerSendErrorMessage(error));
  } finally {
    sendingStickerId.value = null;
  }
};

const openStickerMenu = (event, sticker) => {
  event.preventDefault();
  event.stopPropagation();
  activeMenuStickerId.value = sticker.id;
};

const closeStickerMenu = () => {
  activeMenuStickerId.value = null;
};

const removeSticker = async sticker => {
  deletingStickerId.value = sticker.id;
  try {
    await WhatsmeowStickersAPI.delete(sticker.id);
    stickers.value = stickers.value.filter(item => item.id !== sticker.id);
    closeStickerMenu();
    useAlert(t('CONVERSATION.WHATSMEOW_STICKER.REMOVED'));
  } catch (error) {
    useAlert(t('CONVERSATION.WHATSMEOW_STICKER.SAVE_FAILED'));
  } finally {
    deletingStickerId.value = null;
  }
};

watch(
  () => props.isOpen,
  value => {
    if (value) {
      openedConversationId.value = activeConversationId.value;
      loadStickers();
    } else {
      openedConversationId.value = null;
      closeStickerMenu();
    }
  }
);

watch(activeConversationId, conversationId => {
  if (
    props.isOpen &&
    openedConversationId.value &&
    openedConversationId.value !== conversationId
  ) {
    emit('close');
  }
});
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
          <div
            v-for="sticker in stickers"
            :key="sticker.id"
            class="relative"
            @contextmenu.prevent.stop="openStickerMenu($event, sticker)"
          >
            <button
              type="button"
              class="grid aspect-square w-full place-items-center rounded-xl border border-transparent p-1 [contain-intrinsic-size:5rem_5rem] [content-visibility:auto] hover:border-n-weak hover:bg-n-alpha-1 disabled:opacity-50"
              :disabled="!!sendingStickerId || deletingStickerId === sticker.id"
              @click="sendSticker(sticker)"
            >
              <Icon
                v-if="
                  sendingStickerId === sticker.id ||
                  deletingStickerId === sticker.id
                "
                icon="i-lucide-loader-circle"
                class="size-5 animate-spin text-n-slate-11"
              />
              <span
                v-else-if="!stickerIsAvailable(sticker)"
                class="flex size-20 flex-col items-center justify-center gap-1 rounded-lg bg-n-alpha-1 p-2 text-center text-[0.6875rem] leading-tight text-n-slate-11"
              >
                <Icon icon="i-lucide-circle-off" class="size-4" />
                {{ $t('COMPONENTS.MEDIA.LOADING_FAILED') }}
              </span>
              <img
                v-else
                class="max-h-20 max-w-20 object-contain"
                :src="stickerImageUrl(sticker)"
                :alt="$t('CONVERSATION.WHATSMEOW_STICKER.PREVIEW_TITLE')"
                draggable="false"
                loading="lazy"
                decoding="async"
                fetchpriority="low"
                @load="clearStickerFailed(sticker)"
                @error="setStickerFailed(sticker)"
              />
            </button>
            <div
              v-if="activeMenuStickerId === sticker.id"
              v-on-clickaway="closeStickerMenu"
              class="absolute left-1 top-1 z-[90] w-52 overflow-hidden rounded-xl border border-n-weak bg-n-solid-3 p-1 shadow-xl"
            >
              <button
                type="button"
                class="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-n-ruby-11 hover:bg-n-alpha-2 disabled:opacity-50"
                :disabled="deletingStickerId === sticker.id"
                @click.stop="removeSticker(sticker)"
              >
                <Icon icon="i-lucide-star-off" class="size-4" />
                {{ $t('CONVERSATION.WHATSMEOW_STICKER.REMOVE_FAVORITE') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
