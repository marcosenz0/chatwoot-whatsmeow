<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useElementSize } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { formatDuration } from 'shared/helpers/timeHelper';
import Icon from 'next/icon/Icon.vue';
import Spinner from 'next/spinner/Spinner.vue';

defineProps({
  src: { type: String, required: true },
  poster: { type: String, default: '' },
  autoplay: { type: Boolean, default: false },
});

const emit = defineEmits(['settled']);

const { t } = useI18n();
const video = useTemplateRef('video');
const stage = useTemplateRef('stage');
const { width, height } = useElementSize(stage);
const aspectRatio = ref(16 / 9);
const fittedWidth = computed(() =>
  Math.floor(Math.min(width.value, height.value * aspectRatio.value))
);
const updateAspectRatio = ({ currentTarget }) => {
  const { videoWidth, videoHeight } = currentTarget;
  if (videoWidth && videoHeight) aspectRatio.value = videoWidth / videoHeight;
};
const hasFrame = ref(false);
const isPlaying = ref(false);
const hasError = ref(false);
const currentTime = ref(0);
const duration = ref(0);
const playbackRate = ref(1);
const volume = ref(1);
const isMuted = ref(false);
let previousVolume = 1;

const playbackRates = [0.5, 0.75, 1, 1.25, 1.5, 2];

const showFirstFrame = () => {
  if (hasFrame.value) return;

  hasFrame.value = true;
  emit('settled');
};

const handleError = () => {
  hasError.value = true;
  emit('settled');
};

const togglePlayback = () => {
  if (video.value.paused) {
    video.value.play().catch(() => {
      isPlaying.value = false;
    });
  } else {
    video.value.pause();
  }
};

const syncDuration = event => {
  const seconds = event.currentTarget.duration;
  duration.value = Number.isFinite(seconds) ? seconds : 0;
};

const seek = event => {
  video.value.currentTime = Number(event.target.value);
  currentTime.value = video.value.currentTime;
};

const changePlaybackRate = () => {
  const index = playbackRates.indexOf(playbackRate.value);
  playbackRate.value = playbackRates[(index + 1) % playbackRates.length];
  video.value.playbackRate = playbackRate.value;
};

const syncVolume = element => {
  volume.value = element.volume;
  isMuted.value = element.muted || volume.value === 0;
  if (volume.value > 0) previousVolume = volume.value;
};

const changeVolume = event => {
  video.value.volume = Number(event.target.value);
  video.value.muted = false;
  syncVolume(video.value);
};

const toggleMute = () => {
  if (isMuted.value && volume.value === 0) video.value.volume = previousVolume;
  video.value.muted = !isMuted.value;
  syncVolume(video.value);
};

const displayTime = seconds => formatDuration(Math.floor(seconds));
</script>

<template>
  <div
    ref="stage"
    class="relative flex size-full min-h-0 min-w-0 items-center justify-center"
  >
    <div
      v-if="!hasFrame && !hasError"
      role="status"
      class="pointer-events-none absolute inset-0 grid place-content-center text-n-slate-11"
    >
      <Spinner :size="32" class="motion-reduce:animate-none" />
      <span class="sr-only">{{ t('MARCOX_AI.LOADING') }}</span>
    </div>
    <div
      v-if="hasError"
      class="flex items-center justify-center gap-2 p-5 text-sm text-n-slate-11"
    >
      <Icon icon="i-lucide-circle-off" />
      {{ t('GALLERY_VIEW.MEDIA_UNAVAILABLE') }}
    </div>
    <div
      v-else
      class="group/player relative w-fit max-w-full min-w-0 overflow-hidden rounded-lg bg-black text-white"
      :class="{ invisible: !hasFrame }"
      dir="ltr"
      @click.stop
    >
      <video
        ref="video"
        :src="src"
        :poster="poster || undefined"
        :autoplay="autoplay"
        :width="fittedWidth"
        preload="auto"
        playsinline
        class="skip-context-menu block h-auto max-w-full object-contain"
        @click="togglePlayback"
        @play="isPlaying = true"
        @pause="isPlaying = false"
        @ended="isPlaying = false"
        @durationchange="syncDuration"
        @loadedmetadata="updateAspectRatio"
        @loadeddata="showFirstFrame"
        @canplay="showFirstFrame"
        @resize="updateAspectRatio"
        @timeupdate="currentTime = $event.currentTarget.currentTime"
        @volumechange="syncVolume($event.currentTarget)"
        @error="handleError"
      />
      <button
        v-if="hasFrame && !isPlaying"
        type="button"
        class="absolute left-1/2 top-1/2 grid size-11 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full bg-black/60 hover:bg-black/80 focus-visible:outline focus-visible:outline-white"
        :aria-label="t('MARCOX_AI.RESOURCES.PLAY_VIDEO')"
        @click="togglePlayback"
      >
        <Icon icon="i-lucide-play" class="size-5 fill-current" />
      </button>
      <div
        v-if="hasFrame"
        class="absolute inset-x-0 bottom-0 flex flex-col gap-1 bg-gradient-to-t from-black/85 to-transparent px-2 pb-1 pt-5 transition-opacity group-focus-within/player:pointer-events-auto group-focus-within/player:opacity-100 group-hover/player:pointer-events-auto group-hover/player:opacity-100 motion-reduce:transition-none"
        :class="{
          '[@media(hover:hover)]:pointer-events-none [@media(hover:hover)]:opacity-0':
            isPlaying,
        }"
      >
        <input
          type="range"
          min="0"
          :max="duration"
          step="0.01"
          :value="currentTime"
          :disabled="!duration"
          :aria-label="t('MARCOX_AI.RESOURCES.VIDEO_POSITION')"
          class="reset-base m-0 h-2 w-full min-w-0 cursor-pointer accent-white"
          @input="seek"
          @keydown.left.stop
          @keydown.right.stop
        />
        <div class="flex min-w-0 items-center gap-1">
          <button
            type="button"
            class="grid size-7 shrink-0 place-items-center rounded hover:bg-white/20 focus-visible:outline focus-visible:outline-white"
            :aria-label="
              isPlaying
                ? t('MARCOX_AI.RESOURCES.PAUSE_VIDEO')
                : t('MARCOX_AI.RESOURCES.PLAY_VIDEO')
            "
            @click="togglePlayback"
          >
            <Icon
              :icon="isPlaying ? 'i-lucide-pause' : 'i-lucide-play'"
              class="size-4 fill-current"
            />
          </button>
          <span
            class="min-w-0 flex-1 whitespace-nowrap text-[10px] tabular-nums"
          >
            {{ displayTime(currentTime) + ' / ' + displayTime(duration) }}
          </span>
          <button
            type="button"
            class="h-7 shrink-0 rounded px-1 text-xs font-semibold hover:bg-white/20 focus-visible:outline focus-visible:outline-white"
            :aria-label="
              t('MARCOX_AI.VOICE.SPEED') + ' ' + playbackRate + '\u00d7'
            "
            :title="t('MARCOX_AI.VOICE.SPEED')"
            @click="changePlaybackRate"
          >
            {{ playbackRate + '\u00d7' }}
          </button>
          <div class="group/volume relative flex shrink-0">
            <button
              type="button"
              class="grid size-7 place-items-center rounded hover:bg-white/20 focus-visible:outline focus-visible:outline-white"
              :aria-label="
                isMuted
                  ? t('MARCOX_AI.RESOURCES.UNMUTE_VIDEO')
                  : t('MARCOX_AI.RESOURCES.MUTE_VIDEO')
              "
              @click="toggleMute"
            >
              <Icon
                :icon="isMuted ? 'i-lucide-volume-x' : 'i-lucide-volume-2'"
                class="size-4"
              />
            </button>
            <div
              class="pointer-events-none absolute bottom-full left-1/2 z-10 flex -translate-x-1/2 justify-center rounded-full bg-black/65 p-2 opacity-0 group-focus-within/volume:pointer-events-auto group-focus-within/volume:opacity-100 group-hover/volume:pointer-events-auto group-hover/volume:opacity-100"
            >
              <input
                type="range"
                min="0"
                max="1"
                step="0.01"
                :value="isMuted ? 0 : volume"
                :aria-label="t('MARCOX_AI.VOICE.VOLUME')"
                class="reset-base m-0 h-16 w-2 cursor-pointer accent-white [direction:rtl] [writing-mode:vertical-lr]"
                @input="changeVolume"
                @keydown.left.stop
                @keydown.right.stop
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
