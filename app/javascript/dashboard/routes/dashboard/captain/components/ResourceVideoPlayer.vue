<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatDuration } from 'shared/helpers/timeHelper';

defineProps({
  src: { type: String, required: true },
  name: { type: String, required: true },
});
const { t } = useI18n();
const video = ref(null);
const container = ref(null);
const playing = ref(false);
const muted = ref(true);
const currentTime = ref(0);
const duration = ref(0);
const failed = ref(false);
const fullscreenAvailable = document.fullscreenEnabled;
const togglePlayback = async () => {
  if (playing.value) video.value.pause();
  else {
    try {
      await video.value.play();
    } catch {
      failed.value = true;
    }
  }
};
const seek = event => {
  video.value.currentTime = Number(event.target.value);
  currentTime.value = video.value.currentTime;
};
const fullscreen = async () => {
  if (document.fullscreenElement === container.value)
    await document.exitFullscreen();
  else await container.value.requestFullscreen();
};
</script>

<template>
  <div
    ref="container"
    class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-2 [&:fullscreen]:flex [&:fullscreen]:flex-col [&:fullscreen>video]:aspect-auto [&:fullscreen>video]:min-h-0 [&:fullscreen>video]:max-h-none [&:fullscreen>video]:flex-1"
  >
    <video
      ref="video"
      :src="`${src}#t=0.001`"
      :aria-label="name"
      :muted="muted"
      preload="metadata"
      playsinline
      class="aspect-video max-h-[22rem] w-full bg-n-solid-1 object-contain"
      @loadedmetadata="duration = video.duration"
      @timeupdate="currentTime = video.currentTime"
      @play="playing = true"
      @pause="playing = false"
      @ended="playing = false"
      @error="failed = true"
    />
    <div class="flex items-center gap-2 border-t border-n-weak p-2">
      <Button
        type="button"
        variant="ghost"
        color="slate"
        size="sm"
        :icon="playing ? 'i-lucide-pause' : 'i-lucide-play'"
        :aria-label="
          t(
            playing
              ? 'MARCOX_AI.RESOURCES.PAUSE_VIDEO'
              : 'MARCOX_AI.RESOURCES.PLAY_VIDEO'
          )
        "
        :disabled="failed"
        @click="togglePlayback"
      />
      <span class="shrink-0 text-xs tabular-nums text-n-slate-11">
        {{ formatDuration(Math.floor(currentTime)) }} /
        {{ formatDuration(Math.floor(duration)) }}
      </span>
      <input
        type="range"
        min="0"
        :max="duration || 0"
        step="0.1"
        :value="currentTime"
        :disabled="!duration || failed"
        :aria-label="t('MARCOX_AI.RESOURCES.VIDEO_POSITION')"
        class="reset-base h-1.5 min-w-0 flex-1 cursor-pointer accent-n-blue-9"
        @input="seek"
      />
      <Button
        type="button"
        variant="ghost"
        color="slate"
        size="sm"
        :icon="muted ? 'i-lucide-volume-x' : 'i-lucide-volume-2'"
        :aria-label="
          t(
            muted
              ? 'MARCOX_AI.RESOURCES.UNMUTE_VIDEO'
              : 'MARCOX_AI.RESOURCES.MUTE_VIDEO'
          )
        "
        @click="muted = !muted"
      />
      <Button
        v-if="fullscreenAvailable"
        type="button"
        variant="ghost"
        color="slate"
        size="sm"
        icon="i-lucide-maximize"
        :aria-label="t('MARCOX_AI.RESOURCES.EXPAND_VIDEO')"
        @click="fullscreen"
      />
    </div>
    <p v-if="failed" role="alert" class="m-0 px-3 pb-3 text-xs text-n-ruby-11">
      {{ t('MARCOX_AI.RESOURCES.VIDEO_ERROR') }}
    </p>
  </div>
</template>
