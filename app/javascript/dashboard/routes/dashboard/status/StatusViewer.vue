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

import WhatsmeowStatusesAPI from 'dashboard/api/whatsmeowStatuses';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
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
  isMediaLoading.value = isDurationMedia.value || isImage.value;
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
  isMediaLoading.value = false;
  if (!isPaused.value) playCurrentMedia();
};

const onImageReady = () => {
  isMediaLoading.value = false;
  startTimedProgress();
};

const onMediaError = () => {
  isMediaLoading.value = false;
  isPaused.value = true;
};

const onKeyDown = event => {
  if (event.altKey || event.ctrlKey || event.metaKey) return;

  if (event.key === 'Escape') {
    emit('close');
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
                {{ currentTimestamp }}
              </p>
            </div>
            <button
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
        class="relative flex min-h-0 flex-1 items-center justify-center px-14 pb-6 pt-24 sm:px-24"
      >
        <div
          v-if="isImage && currentStatus.media?.url"
          class="absolute inset-0 overflow-hidden"
          aria-hidden="true"
        >
          <img
            :src="currentStatus.media.url"
            alt=""
            class="h-full w-full scale-110 object-cover opacity-40 blur-3xl"
          />
          <span class="absolute inset-0 bg-black/50" />
        </div>

        <div
          v-if="currentType === 'text'"
          class="relative z-10 flex aspect-[9/16] max-h-[calc(100dvh-7rem)] w-full max-w-[28rem] items-center justify-center overflow-hidden rounded-md p-8 shadow-2xl"
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
          class="relative z-10 flex max-h-[calc(100dvh-7rem)] max-w-full items-center justify-center overflow-hidden rounded-md bg-black shadow-2xl"
          :class="{
            'aspect-[9/16] w-full max-w-[28rem] bg-n-slate-11': isAudio,
          }"
        >
          <Spinner
            v-if="isMediaLoading"
            :size="32"
            class="absolute z-10 text-white motion-reduce:animate-none"
          />
          <video
            v-if="currentType === 'video'"
            ref="mediaRef"
            :key="currentStatus.id"
            :src="currentStatus.media?.url"
            playsinline
            class="max-h-[calc(100dvh-7rem)] max-w-full object-contain"
            @timeupdate="onMediaTimeUpdate"
            @ended="nextStatus"
            @playing="isPaused = false"
            @pause="onMediaPause"
            @canplay="onMediaReady"
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
            class="max-h-[calc(100dvh-7rem)] max-w-full object-contain"
            @load="onImageReady"
            @error="onImageReady"
          />

          <div
            v-if="currentStatus.content"
            class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/90 via-black/60 to-transparent px-5 pb-5 pt-12 text-center"
          >
            <p class="mb-0 whitespace-pre-wrap text-sm leading-6 text-white">
              {{ currentStatus.content }}
            </p>
          </div>
        </div>
      </main>

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
