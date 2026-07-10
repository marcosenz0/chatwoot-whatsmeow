<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import WhatsmeowStatusesAPI from 'dashboard/api/whatsmeowStatuses';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import EmojiInput from 'shared/components/emoji/EmojiInput.vue';
import StatusStickerPicker from './StatusStickerPicker.vue';
import { useStatusTime } from './useStatusTime';

const props = defineProps({
  groups: {
    type: Array,
    required: true,
  },
  initialGroupIndex: {
    type: Number,
    default: 0,
  },
  initialStatusIndex: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['close', 'viewed']);

const { t } = useI18n();
const { formatStatusTime } = useStatusTime();

const TIMED_STATUS_DURATION = 5000;

const closeButtonRef = ref(null);
const mediaRef = ref(null);
const groupIndex = ref(
  Math.min(Math.max(props.initialGroupIndex, 0), props.groups.length - 1)
);
const statusIndex = ref(Math.max(props.initialStatusIndex, 0));
const progress = ref(0);
const isPaused = ref(false);
const isMediaLoading = ref(false);
const hasMediaError = ref(false);
const isMuted = ref(false);
const generatedVideoBackdropUrl = ref('');
const replyText = ref('');
const isReplying = ref(false);
const showEmojiPicker = ref(false);
const showStickerPicker = ref(false);
const showViewers = ref(false);
const isLoadingViewers = ref(false);
const viewers = ref([]);
const viewersStatusId = ref(null);

let progressFrame = null;
let progressStartedAt = 0;
let pausedByVisibility = false;

const currentGroup = computed(() => props.groups[groupIndex.value]);
const currentStatus = computed(
  () => currentGroup.value?.items[statusIndex.value]
);
const currentType = computed(() => currentStatus.value?.status_type || 'text');
const isVideo = computed(() => currentType.value === 'video');
const isAudio = computed(() => currentType.value === 'audio');
const isImage = computed(() => currentType.value === 'image');
const isDurationMedia = computed(() => isVideo.value || isAudio.value);
const isMediaBacked = computed(
  () =>
    (isVideo.value || isImage.value) && Boolean(currentStatus.value?.media?.url)
);
const videoThumbnailUrl = computed(() => {
  const metadata = currentStatus.value?.metadata || {};
  const data = metadata.thumbnail_base64;
  if (!data) return '';

  return `data:${metadata.thumbnail_content_type || 'image/jpeg'};base64,${data}`;
});
const videoBackdropUrl = computed(
  () => videoThumbnailUrl.value || generatedVideoBackdropUrl.value
);
const isOwnStatus = computed(() => Boolean(currentStatus.value?.from_me));
const canReply = computed(() => !isOwnStatus.value);
const viewerCount = computed(() =>
  Number(currentStatus.value?.viewer_count || 0)
);
const canGoPrevious = computed(
  () => statusIndex.value > 0 || groupIndex.value > 0
);

const BACKGROUND_CLASSES = {
  teal: 'bg-n-teal-9',
  blue: 'bg-n-blue-9',
  violet: 'bg-n-violet-9',
  amber: 'bg-n-amber-9',
  ruby: 'bg-n-ruby-9',
  slate: 'bg-n-slate-11',
  FF0B8467: 'bg-n-teal-9',
  FF176BCE: 'bg-n-blue-9',
  FF6750A4: 'bg-n-violet-9',
  FFB85C00: 'bg-n-amber-9',
  FFA6294F: 'bg-n-ruby-9',
  FF30363D: 'bg-n-slate-11',
};

const FONT_CLASSES = {
  system: 'font-normal',
  bold: 'font-bold',
  serif: 'font-serif',
  modern: 'font-medium tracking-wide',
  mono: 'font-mono',
  0: 'font-normal',
  6: 'font-bold',
  8: 'font-serif',
  9: 'font-medium tracking-wide',
  10: 'font-mono',
};

const TEXT_COLOR_CLASSES = {
  FFFFFFFF: 'text-white',
  FF000000: 'text-black',
};

const argbKey = value => {
  const number = Number(value);
  if (!Number.isFinite(number)) return '';
  return number.toString(16).padStart(8, '0').toUpperCase();
};

const statusBackgroundClass = computed(() => {
  const metadata = currentStatus.value?.metadata || {};
  return (
    BACKGROUND_CLASSES[metadata.background] ||
    BACKGROUND_CLASSES[argbKey(metadata.background_argb)] ||
    BACKGROUND_CLASSES.slate
  );
});

const statusFontClass = computed(() => {
  const metadata = currentStatus.value?.metadata || {};
  return (
    FONT_CLASSES[metadata.font] ||
    FONT_CLASSES[metadata.font_value] ||
    FONT_CLASSES.system
  );
});

const statusTextClass = computed(() => {
  const metadata = currentStatus.value?.metadata || {};
  return [
    statusFontClass.value,
    TEXT_COLOR_CLASSES[argbKey(metadata.text_argb)] || 'text-white',
  ];
});

const currentTimestamp = computed(() =>
  currentStatus.value?.posted_at
    ? formatStatusTime(currentStatus.value.posted_at)
    : ''
);
const currentMetadataLine = computed(() => {
  const inboxName = currentStatus.value?.inbox_name;
  if (!inboxName) return currentTimestamp.value;

  return t('WHATSAPP_STATUS.VIEWER.INBOX_TIME', {
    inbox: inboxName,
    time: currentTimestamp.value,
  });
});

const segmentValue = index => {
  if (index < statusIndex.value) return 1;
  if (index > statusIndex.value) return 0;
  return progress.value;
};

const cancelProgressFrame = () => {
  if (!progressFrame) return;
  cancelAnimationFrame(progressFrame);
  progressFrame = null;
};

const closeMenus = () => {
  showEmojiPicker.value = false;
  showStickerPicker.value = false;
};

const nextStatus = () => {
  const group = currentGroup.value;
  if (statusIndex.value < group.items.length - 1) {
    statusIndex.value += 1;
    return;
  }

  if (groupIndex.value < props.groups.length - 1) {
    groupIndex.value += 1;
    statusIndex.value = 0;
    return;
  }

  emit('close');
};

const previousStatus = () => {
  if (!canGoPrevious.value) {
    progress.value = 0;
    return;
  }

  if (statusIndex.value > 0) {
    statusIndex.value -= 1;
    return;
  }

  groupIndex.value -= 1;
  statusIndex.value = props.groups[groupIndex.value].items.length - 1;
};

const tickTimedProgress = timestamp => {
  const elapsed = timestamp - progressStartedAt;
  progress.value = Math.min(elapsed / TIMED_STATUS_DURATION, 1);

  if (progress.value >= 1) {
    progressFrame = null;
    nextStatus();
    return;
  }

  progressFrame = requestAnimationFrame(tickTimedProgress);
};

const startTimedProgress = () => {
  cancelProgressFrame();
  if (isPaused.value || isDurationMedia.value) return;

  progressStartedAt =
    performance.now() - progress.value * TIMED_STATUS_DURATION;
  progressFrame = requestAnimationFrame(tickTimedProgress);
};

const playCurrentMedia = async () => {
  if (!mediaRef.value) return;

  try {
    await mediaRef.value.play();
    isPaused.value = false;
  } catch {
    if (isVideo.value && !isMuted.value) {
      isMuted.value = true;
      await nextTick();
      try {
        await mediaRef.value.play();
        isPaused.value = false;
        return;
      } catch {
        // A user gesture will still be able to start this media.
      }
    }
    isPaused.value = true;
  }
};

const markCurrentViewed = async () => {
  const status = currentStatus.value;
  if (!status || status.from_me || status.viewed) return;

  emit('viewed', status.id);
  try {
    await WhatsmeowStatusesAPI.markViewed(status.id);
  } catch {
    // Viewing remains optimistic; the next list refresh reconciles server state.
  }
};

const prepareCurrentStatus = async () => {
  cancelProgressFrame();
  progress.value = 0;
  isPaused.value = false;
  hasMediaError.value = false;
  isMediaLoading.value = isDurationMedia.value || isImage.value;
  generatedVideoBackdropUrl.value = '';
  replyText.value = '';
  showViewers.value = false;
  viewers.value = [];
  viewersStatusId.value = null;
  closeMenus();
  markCurrentViewed();
  await nextTick();

  if (isDurationMedia.value) {
    await playCurrentMedia();
  } else if (!isImage.value) {
    startTimedProgress();
  }
};

const togglePause = () => {
  if (isDurationMedia.value && mediaRef.value) {
    if (mediaRef.value.paused) {
      playCurrentMedia();
    } else {
      mediaRef.value.pause();
      isPaused.value = true;
    }
    return;
  }

  isPaused.value = !isPaused.value;
  if (isPaused.value) cancelProgressFrame();
  else startTimedProgress();
};

const toggleMute = () => {
  isMuted.value = !isMuted.value;
  if (mediaRef.value) mediaRef.value.muted = isMuted.value;
  if (!isPaused.value) playCurrentMedia();
};

const onMediaTimeUpdate = event => {
  const { currentTime, duration } = event.currentTarget;
  progress.value =
    Number.isFinite(duration) && duration > 0 ? currentTime / duration : 0;
};

const onMediaPause = event => {
  if (isDurationMedia.value && !event.currentTarget.ended) {
    isPaused.value = true;
  }
};

const onMediaReady = () => {
  hasMediaError.value = false;
  isMediaLoading.value = false;
  if (!isPaused.value) playCurrentMedia();
};

const captureVideoBackdrop = event => {
  if (videoThumbnailUrl.value || generatedVideoBackdropUrl.value) return;

  const video = event.currentTarget;
  if (!video.videoWidth || !video.videoHeight) return;

  try {
    const canvas = document.createElement('canvas');
    const width = 96;
    const height = Math.max(
      1,
      Math.round((video.videoHeight / video.videoWidth) * width)
    );
    canvas.width = width;
    canvas.height = height;
    canvas.getContext('2d')?.drawImage(video, 0, 0, width, height);
    generatedVideoBackdropUrl.value = canvas.toDataURL('image/jpeg', 0.65);
  } catch {
    // Rendering the foreground video is still the primary experience.
  }
};

const onVideoLoaded = event => {
  captureVideoBackdrop(event);
  onMediaReady();
};

const onImageReady = () => {
  isMediaLoading.value = false;
  startTimedProgress();
};

const onMediaError = () => {
  isMediaLoading.value = false;
  hasMediaError.value = true;
  isPaused.value = true;
};

const sendReply = async () => {
  const content = replyText.value.trim();
  if (!content || !canReply.value || isReplying.value) return;

  isReplying.value = true;
  try {
    await WhatsmeowStatusesAPI.reply(currentStatus.value.id, { content });
    replyText.value = '';
    useAlert(t('WHATSAPP_STATUS.VIEWER.REPLY_SENT'));
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('WHATSAPP_STATUS.VIEWER.REPLY_ERROR')
    );
  } finally {
    isReplying.value = false;
  }
};

const sendReaction = async emoji => {
  if (!emoji || !canReply.value || isReplying.value) return;

  closeMenus();
  isReplying.value = true;
  try {
    await WhatsmeowStatusesAPI.reply(currentStatus.value.id, {
      reaction: emoji,
    });
    useAlert(t('WHATSAPP_STATUS.VIEWER.REACTION_SENT'));
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('WHATSAPP_STATUS.VIEWER.REPLY_ERROR')
    );
  } finally {
    isReplying.value = false;
  }
};

const sendSticker = async sticker => {
  if (!sticker?.id || !canReply.value || isReplying.value) return;

  closeMenus();
  isReplying.value = true;
  try {
    await WhatsmeowStatusesAPI.reply(currentStatus.value.id, {
      sticker_id: sticker.id,
    });
    useAlert(t('WHATSAPP_STATUS.VIEWER.STICKER_SENT'));
  } catch (error) {
    useAlert(
      error.response?.data?.message || t('WHATSAPP_STATUS.VIEWER.REPLY_ERROR')
    );
  } finally {
    isReplying.value = false;
  }
};

const openViewers = async () => {
  if (!isOwnStatus.value) return;

  showViewers.value = true;
  if (viewersStatusId.value === currentStatus.value.id) return;

  isLoadingViewers.value = true;
  try {
    const { data } = await WhatsmeowStatusesAPI.getViewers(
      currentStatus.value.id
    );
    viewers.value = data.payload || [];
    viewersStatusId.value = currentStatus.value.id;
  } catch (error) {
    showViewers.value = false;
    useAlert(
      error.response?.data?.message || t('WHATSAPP_STATUS.VIEWER.VIEWERS_ERROR')
    );
  } finally {
    isLoadingViewers.value = false;
  }
};

const onKeyDown = event => {
  if (event.altKey || event.ctrlKey || event.metaKey) return;
  if (['INPUT', 'TEXTAREA'].includes(event.target?.tagName)) return;

  if (event.key === 'Escape') {
    if (showViewers.value) showViewers.value = false;
    else if (showEmojiPicker.value || showStickerPicker.value) closeMenus();
    else emit('close');
  } else if (event.key === 'ArrowRight') {
    nextStatus();
  } else if (event.key === 'ArrowLeft') {
    previousStatus();
  } else if (event.key === ' ') {
    event.preventDefault();
    togglePause();
  }
};

const onVisibilityChange = () => {
  if (document.visibilityState === 'hidden' && !isPaused.value) {
    pausedByVisibility = true;
    togglePause();
  } else if (document.visibilityState === 'visible' && pausedByVisibility) {
    pausedByVisibility = false;
    togglePause();
  }
};

watch([groupIndex, statusIndex], prepareCurrentStatus, { immediate: true });

onMounted(() => {
  window.addEventListener('keydown', onKeyDown);
  document.addEventListener('visibilitychange', onVisibilityChange);
  nextTick(() => closeButtonRef.value?.focus());
});

onBeforeUnmount(() => {
  cancelProgressFrame();
  window.removeEventListener('keydown', onKeyDown);
  document.removeEventListener('visibilitychange', onVisibilityChange);
});
</script>

<template>
  <TeleportWithDirection to="body">
    <section
      role="dialog"
      aria-modal="true"
      :aria-label="t('WHATSAPP_STATUS.TITLE')"
      class="fixed inset-0 z-[1000] flex min-h-dvh flex-col overflow-hidden bg-black text-white"
    >
      <header
        class="absolute inset-x-0 top-0 z-30 flex items-start justify-center px-4 pb-4 pt-4 sm:px-8"
      >
        <div class="w-full max-w-[34rem] pr-12 sm:pr-0">
          <div class="flex w-full gap-1" aria-hidden="true">
            <progress
              v-for="(_, index) in currentGroup.items"
              :key="index"
              :value="segmentValue(index)"
              max="1"
              class="h-1 min-w-0 flex-1 appearance-none overflow-hidden rounded-full border-0 bg-white/30 [&::-moz-progress-bar]:bg-white [&::-webkit-progress-bar]:bg-white/30 [&::-webkit-progress-value]:bg-white"
            />
          </div>

          <div class="mt-4 flex items-center gap-3">
            <Avatar
              :name="currentGroup.name"
              :src="currentGroup.avatar"
              :size="36"
              rounded-full
            />
            <div class="min-w-0 flex-1">
              <p class="mb-0 truncate text-sm font-semibold text-white">
                {{ currentGroup.name }}
              </p>
              <p class="mb-0 text-xs text-white/70">
                {{ currentMetadataLine }}
              </p>
            </div>
            <button
              v-if="isVideo || isAudio"
              type="button"
              class="flex size-11 items-center justify-center rounded-full text-white transition-colors hover:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
              :aria-label="
                isPaused
                  ? t('WHATSAPP_STATUS.VIEWER.PLAY')
                  : t('WHATSAPP_STATUS.VIEWER.PAUSE')
              "
              @click="togglePause"
            >
              <Icon
                :icon="isPaused ? 'i-lucide-play' : 'i-lucide-pause'"
                class="size-5"
              />
            </button>
            <button
              v-if="isVideo || isAudio"
              type="button"
              class="flex size-11 items-center justify-center rounded-full text-white transition-colors hover:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
              :aria-label="
                isMuted
                  ? t('WHATSAPP_STATUS.VIEWER.UNMUTE')
                  : t('WHATSAPP_STATUS.VIEWER.MUTE')
              "
              @click="toggleMute"
            >
              <Icon
                :icon="isMuted ? 'i-lucide-volume-x' : 'i-lucide-volume-2'"
                class="size-5"
              />
            </button>
          </div>
        </div>

        <button
          ref="closeButtonRef"
          type="button"
          class="absolute right-3 top-3 flex size-12 items-center justify-center rounded-full text-white transition-colors hover:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white sm:right-6 sm:top-4"
          :aria-label="t('WHATSAPP_STATUS.VIEWER.CLOSE')"
          @click="emit('close')"
        >
          <Icon icon="i-lucide-x" class="size-6" />
        </button>
      </header>

      <main
        class="relative flex min-h-0 flex-1 items-center justify-center px-14 pb-24 pt-24 sm:px-24"
      >
        <div
          v-if="isMediaBacked"
          class="pointer-events-none absolute inset-0 overflow-hidden bg-black"
          aria-hidden="true"
        >
          <img
            v-if="isVideo && videoBackdropUrl"
            :src="videoBackdropUrl"
            alt=""
            class="h-full w-full scale-125 object-cover opacity-80 blur-[52px] saturate-125"
          />
          <span
            v-else-if="isVideo"
            class="absolute inset-0 bg-gradient-to-br from-n-slate-9 via-black to-n-slate-10"
          />
          <img
            v-else
            :src="currentStatus.media.url"
            alt=""
            class="h-full w-full scale-125 object-cover opacity-80 blur-[52px] saturate-125"
          />
          <span class="absolute inset-0 bg-black/40" />
          <span
            class="absolute inset-0 bg-gradient-to-b from-black/35 via-transparent to-black/75"
          />
        </div>

        <div
          v-if="currentType === 'text'"
          class="relative z-10 flex aspect-[9/16] max-h-[calc(100dvh-9rem)] w-full max-w-[28rem] items-center justify-center overflow-hidden rounded-md p-8 shadow-2xl"
          :class="statusBackgroundClass"
        >
          <p
            class="mb-0 max-w-full whitespace-pre-wrap break-words text-center text-2xl leading-relaxed sm:text-3xl"
            :class="statusTextClass"
          >
            {{ currentStatus.content }}
          </p>
        </div>

        <div
          v-else
          class="relative z-10 flex max-h-[calc(100dvh-9rem)] max-w-full items-center justify-center overflow-hidden rounded-md bg-black shadow-2xl"
          :class="{
            'aspect-[9/16] w-full max-w-[28rem] bg-n-slate-11':
              isAudio || hasMediaError,
          }"
        >
          <Spinner
            v-if="isMediaLoading"
            :size="32"
            class="absolute z-10 text-white motion-reduce:animate-none"
          />
          <div
            v-if="hasMediaError"
            class="relative flex h-full w-full flex-col items-center justify-center gap-3 overflow-hidden p-8 text-center"
          >
            <img
              v-if="videoBackdropUrl"
              :src="videoBackdropUrl"
              alt=""
              class="absolute inset-0 h-full w-full object-cover opacity-35 blur-sm"
            />
            <span class="absolute inset-0 bg-black/55" />
            <span
              class="relative z-10 flex size-14 items-center justify-center rounded-full bg-white/10"
            >
              <Icon icon="i-lucide-circle-alert" class="size-6 text-white" />
            </span>
            <p class="relative mb-0 max-w-xs text-sm leading-6 text-white/80">
              {{ t('WHATSAPP_STATUS.VIEWER.MEDIA_UNAVAILABLE') }}
            </p>
          </div>
          <video
            v-else-if="currentType === 'video'"
            ref="mediaRef"
            :key="currentStatus.id"
            :src="currentStatus.media?.url"
            :muted="isMuted"
            playsinline
            preload="metadata"
            class="max-h-[calc(100dvh-9rem)] max-w-full object-contain"
            @timeupdate="onMediaTimeUpdate"
            @ended="nextStatus"
            @playing="isPaused = false"
            @pause="onMediaPause"
            @canplay="onMediaReady"
            @loadeddata="onVideoLoaded"
            @waiting="isMediaLoading = true"
            @error="onMediaError"
          >
            {{ t('WHATSAPP_STATUS.VIEWER.VIDEO_UNAVAILABLE') }}
          </video>
          <div
            v-else-if="currentType === 'audio'"
            class="flex h-full w-full flex-col items-center justify-center gap-6 p-6"
          >
            <span
              class="flex size-20 items-center justify-center rounded-full bg-white/10 text-white"
            >
              <Icon icon="i-lucide-mic-2" class="size-9" />
            </span>
            <p class="mb-0 text-base font-semibold text-white">
              {{ t('WHATSAPP_STATUS.VIEWER.VOICE_STATUS') }}
            </p>
            <audio
              ref="mediaRef"
              :key="currentStatus.id"
              :src="currentStatus.media?.url"
              :muted="isMuted"
              controls
              preload="auto"
              class="w-full max-w-sm"
              @timeupdate="onMediaTimeUpdate"
              @ended="nextStatus"
              @playing="isPaused = false"
              @pause="onMediaPause"
              @canplay="onMediaReady"
              @waiting="isMediaLoading = true"
              @error="onMediaError"
            >
              {{ t('WHATSAPP_STATUS.VIEWER.AUDIO_UNAVAILABLE') }}
            </audio>
          </div>
          <img
            v-else
            :key="currentStatus.id"
            :src="currentStatus.media?.url"
            :alt="
              t('WHATSAPP_STATUS.VIEWER.IMAGE_ALT', {
                name: currentGroup.name,
              })
            "
            class="max-h-[calc(100dvh-9rem)] max-w-full object-contain"
            @load="onImageReady"
            @error="onMediaError"
          />

          <div
            v-if="currentStatus.content && !hasMediaError"
            class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/95 via-black/65 to-transparent px-5 pb-5 pt-12 text-center"
          >
            <p class="mb-0 whitespace-pre-wrap text-sm leading-6 text-white">
              {{ currentStatus.content }}
            </p>
          </div>
        </div>
      </main>

      <div
        v-if="canReply"
        class="absolute inset-x-0 bottom-0 z-30 flex justify-center px-4 pb-4 sm:px-8"
      >
        <div class="relative flex w-full max-w-[34rem] items-end gap-2">
          <StatusStickerPicker
            :is-open="showStickerPicker"
            @close="showStickerPicker = false"
            @select="sendSticker"
          />
          <div
            class="relative flex min-w-0 flex-1 items-center rounded-xl bg-black/70 px-2 shadow-lg ring-1 ring-white/15 backdrop-blur-xl"
          >
            <button
              type="button"
              class="flex size-10 flex-shrink-0 items-center justify-center rounded-lg text-white/75 transition-colors hover:bg-white/10 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
              :aria-label="t('WHATSAPP_STATUS.VIEWER.ADD_EMOJI')"
              @click="showEmojiPicker = !showEmojiPicker"
            >
              <Icon icon="i-lucide-smile" class="size-5" />
            </button>
            <div class="relative flex-shrink-0">
              <EmojiInput
                v-if="showEmojiPicker"
                v-on-clickaway="() => (showEmojiPicker = false)"
                class="!bottom-14 !left-0 !right-auto !top-auto !w-[calc(100vw-2rem)] sm:!w-80"
                :on-click="sendReaction"
              />
            </div>
            <button
              type="button"
              class="flex size-10 flex-shrink-0 items-center justify-center rounded-lg text-white/75 transition-colors hover:bg-white/10 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
              :aria-label="t('WHATSAPP_STATUS.VIEWER.ADD_STICKER')"
              @click="showStickerPicker = !showStickerPicker"
            >
              <Icon icon="i-lucide-sticker" class="size-5" />
            </button>
            <input
              v-model="replyText"
              type="text"
              maxlength="4096"
              class="reset-base min-h-11 min-w-0 flex-1 bg-transparent px-2 text-sm text-white outline-none placeholder:text-white/55"
              :placeholder="t('WHATSAPP_STATUS.VIEWER.REPLY_PLACEHOLDER')"
              @keydown.enter.prevent="sendReply"
            />
          </div>
          <button
            type="button"
            class="flex size-11 flex-shrink-0 items-center justify-center rounded-full bg-white text-black shadow-lg transition-transform hover:scale-105 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white disabled:cursor-not-allowed disabled:opacity-40 motion-reduce:transition-none"
            :disabled="!replyText.trim() || isReplying"
            :aria-label="t('WHATSAPP_STATUS.VIEWER.SEND_REPLY')"
            @click="sendReply"
          >
            <Icon
              :icon="isReplying ? 'i-lucide-loader-circle' : 'i-lucide-send'"
              class="size-5"
              :class="{ 'animate-spin motion-reduce:animate-none': isReplying }"
            />
          </button>
        </div>
      </div>

      <div
        v-else
        class="absolute inset-x-0 bottom-0 z-30 flex justify-center px-4 pb-4 sm:px-8"
      >
        <div class="relative flex w-full max-w-[34rem] justify-center">
          <button
            type="button"
            class="flex min-h-11 items-center gap-2 rounded-full bg-black/70 px-4 text-sm text-white shadow-lg ring-1 ring-white/15 backdrop-blur-xl transition-colors hover:bg-black/85 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
            :aria-label="t('WHATSAPP_STATUS.VIEWER.SEE_VIEWERS')"
            @click="openViewers"
          >
            <Icon icon="i-lucide-eye" class="size-4" />
            {{
              t('WHATSAPP_STATUS.VIEWER.VIEWERS_COUNT', {
                count: viewerCount,
              })
            }}
          </button>

          <div
            v-if="showViewers"
            v-on-clickaway="() => (showViewers = false)"
            class="absolute bottom-14 left-1/2 z-40 max-h-80 w-full max-w-sm -translate-x-1/2 overflow-hidden rounded-xl border border-white/15 bg-black/95 shadow-2xl backdrop-blur-xl"
            role="dialog"
            :aria-label="t('WHATSAPP_STATUS.VIEWER.VIEWERS_TITLE')"
          >
            <div
              class="flex items-center justify-between border-b border-white/10 px-4 py-3"
            >
              <div>
                <p class="mb-0 text-sm font-semibold text-white">
                  {{ t('WHATSAPP_STATUS.VIEWER.VIEWERS_TITLE') }}
                </p>
                <p class="mb-0 mt-0.5 text-xs text-white/60">
                  {{
                    t('WHATSAPP_STATUS.VIEWER.VIEWERS_COUNT', {
                      count: viewers.length,
                    })
                  }}
                </p>
              </div>
              <button
                type="button"
                class="flex size-9 items-center justify-center rounded-lg text-white/75 transition-colors hover:bg-white/10 hover:text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
                :aria-label="t('WHATSAPP_STATUS.VIEWER.CLOSE_VIEWERS')"
                @click="showViewers = false"
              >
                <Icon icon="i-lucide-x" class="size-4" />
              </button>
            </div>
            <div class="max-h-64 overflow-y-auto p-2">
              <div
                v-if="isLoadingViewers"
                class="flex h-24 items-center justify-center"
              >
                <Spinner :size="22" class="text-white" />
              </div>
              <p
                v-else-if="!viewers.length"
                class="m-0 px-3 py-8 text-center text-sm text-white/65"
              >
                {{ t('WHATSAPP_STATUS.VIEWER.NO_VIEWERS') }}
              </p>
              <div v-else class="flex flex-col gap-1">
                <div
                  v-for="viewer in viewers"
                  :key="viewer.id || viewer.viewer_jid"
                  class="flex min-h-12 items-center gap-3 rounded-lg px-2 py-1.5"
                >
                  <Avatar
                    :name="viewer.contact?.name || viewer.viewer_name"
                    :src="viewer.contact?.avatar_url"
                    :size="36"
                    rounded-full
                  />
                  <span class="min-w-0 flex-1">
                    <span class="block truncate text-sm font-medium text-white">
                      {{ viewer.contact?.name || viewer.viewer_name }}
                    </span>
                    <span class="block truncate text-xs text-white/60">
                      {{ formatStatusTime(viewer.viewed_at) }}
                    </span>
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <button
        type="button"
        class="absolute left-2 top-1/2 z-20 flex size-12 -translate-y-1/2 items-center justify-center rounded-full bg-black/50 text-white transition-colors hover:bg-black/70 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white disabled:cursor-not-allowed disabled:opacity-30 sm:left-6"
        :disabled="!canGoPrevious"
        :aria-label="t('WHATSAPP_STATUS.VIEWER.PREVIOUS')"
        @click="previousStatus"
      >
        <Icon icon="i-lucide-chevron-left" class="size-7" />
      </button>

      <button
        type="button"
        class="absolute right-2 top-1/2 z-20 flex size-12 -translate-y-1/2 items-center justify-center rounded-full bg-black/50 text-white transition-colors hover:bg-black/70 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white sm:right-6"
        :aria-label="t('WHATSAPP_STATUS.VIEWER.NEXT')"
        @click="nextStatus"
      >
        <Icon icon="i-lucide-chevron-right" class="size-7" />
      </button>
    </section>
  </TeleportWithDirection>
</template>
