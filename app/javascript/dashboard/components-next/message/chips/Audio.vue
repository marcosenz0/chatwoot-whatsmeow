<script setup>
import {
  computed,
  getCurrentInstance,
  onMounted,
  ref,
  useTemplateRef,
} from 'vue';
import Icon from 'next/icon/Icon.vue';
import Avatar from 'next/avatar/Avatar.vue';
import { timeStampAppendedURL } from 'dashboard/helper/URLHelper';
import { useEmitter } from 'dashboard/composables/emitter';
import { emitter } from 'shared/helpers/mitt';
import { ORIENTATION } from '../constants';
import { useMessageContext } from '../provider.js';

const props = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
  showTranscribedText: {
    type: Boolean,
    default: true,
  },
});

defineOptions({
  inheritAttrs: false,
});

const { contentAttributes, orientation, sender } = useMessageContext();

const timeStampURL = computed(() => {
  if (!props.attachment.dataUrl) return '';
  return timeStampAppendedURL(props.attachment.dataUrl);
});

const TRANSCRIPT_PREVIEW_LENGTH = 200;
const isTranscriptExpanded = ref(false);
const isTranscriptLong = computed(
  () =>
    (props.attachment.transcribedText?.length || 0) > TRANSCRIPT_PREVIEW_LENGTH
);
const displayedTranscript = computed(() => {
  const text = props.attachment.transcribedText || '';
  if (!isTranscriptLong.value || isTranscriptExpanded.value) return text;
  return `${text.slice(0, TRANSCRIPT_PREVIEW_LENGTH).trimEnd()}...`;
});

const audioMeta = computed(() => props.attachment.meta || {});
const contentType = computed(() => {
  const rawContentType = String(
    props.attachment.contentType || props.attachment.content_type || ''
  );
  return rawContentType.split(';')[0].trim().toLowerCase();
});
const extension = computed(() =>
  String(props.attachment.extension || '').toLowerCase()
);
const isOutgoing = computed(() => orientation.value === ORIENTATION.RIGHT);
const isRecordedAudio = computed(() => {
  const meta = audioMeta.value;
  const attributes = contentAttributes.value || {};

  return Boolean(
    meta.recorded_audio ||
      meta.recordedAudio ||
      meta.whatsmeow_recorded_audio ||
      meta.whatsmeowRecordedAudio ||
      meta.ptt ||
      meta.PTT ||
      meta.voice_note ||
      meta.voiceNote ||
      attributes.whatsmeow_recorded_audio ||
      attributes.whatsmeowRecordedAudio ||
      contentType.value === 'audio/ogg' ||
      contentType.value === 'audio/opus' ||
      ['ogg', 'opus'].includes(extension.value)
  );
});

const avatarName = computed(() => sender.value?.name || '');
const avatarSrc = computed(
  () =>
    sender.value?.thumbnail ||
    sender.value?.avatarUrl ||
    sender.value?.avatar_url ||
    ''
);
const metaDuration = computed(() =>
  Number(
    audioMeta.value.duration_seconds || audioMeta.value.durationSeconds || 0
  )
);

const audioPlayer = useTemplateRef('audioPlayer');

const isPlaying = ref(false);
const currentTime = ref(0);
const duration = ref(0);
const playbackSpeed = ref(1);
const hasPlayableSource = computed(() => Boolean(timeStampURL.value));

const { uid } = getCurrentInstance();

const setDuration = value => {
  if (Number.isFinite(value) && value > 0) duration.value = value;
};

const resolveStreamingDuration = () => {
  const el = audioPlayer.value;
  if (!el) return;
  const onTimeUpdate = () => {
    el.removeEventListener('timeupdate', onTimeUpdate);
    el.currentTime = 0;
    setDuration(el.duration);
  };
  el.addEventListener('timeupdate', onTimeUpdate);
  try {
    el.currentTime = Number.MAX_SAFE_INTEGER;
  } catch {
    el.removeEventListener('timeupdate', onTimeUpdate);
  }
};

const syncDuration = () => {
  const d = audioPlayer.value?.duration;
  setDuration(d);
};

const onLoadedMetadata = () => {
  const d = audioPlayer.value?.duration;
  if (!Number.isFinite(d) || d <= 0) {
    resolveStreamingDuration();
    return;
  }
  setDuration(d);
};

const effectiveDuration = computed(() => duration.value || metaDuration.value);
const playbackSpeedLabel = computed(() => `${playbackSpeed.value}x`);

const formatTime = time => {
  if (!time || Number.isNaN(time)) return '00:00';
  const minutes = Math.floor(time / 60);
  const seconds = Math.floor(time % 60);
  return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
};

const displayTime = computed(() => {
  if (isPlaying.value || currentTime.value > 0)
    return formatTime(currentTime.value);
  return formatTime(effectiveDuration.value);
});

const DEFAULT_VOICE_WAVEFORM = [
  1, 2, 1, 3, 2, 4, 2, 5, 3, 6, 4, 3, 5, 2, 4, 6, 3, 2, 5, 4, 6, 3, 2, 4, 5, 2,
  3, 6, 4, 2, 5, 3, 2, 4, 6, 5, 3, 1, 4, 2, 5, 3, 2, 1,
];
const FLAT_WAVEFORM = Array.from({ length: 36 }, () => 1);
const decodedWaveform = computed(() => {
  const rawWaveform = audioMeta.value.waveform;
  if (Array.isArray(rawWaveform)) {
    return rawWaveform
      .map(value => Math.max(1, Math.min(6, Math.round(Number(value) || 1))))
      .slice(0, 48);
  }
  if (!rawWaveform || typeof rawWaveform !== 'string') return [];

  try {
    const binary = atob(rawWaveform);
    return Array.from(binary)
      .map(value =>
        Math.max(1, Math.min(6, Math.round((value.charCodeAt(0) / 255) * 6)))
      )
      .slice(0, 48);
  } catch {
    return [];
  }
});
const waveformBars = computed(() => {
  if (!isRecordedAudio.value) return FLAT_WAVEFORM;
  return decodedWaveform.value.length
    ? decodedWaveform.value
    : DEFAULT_VOICE_WAVEFORM;
});
const activeBarCount = computed(() => {
  if (!effectiveDuration.value) return 0;
  return Math.round(
    (currentTime.value / effectiveDuration.value) * waveformBars.value.length
  );
});
const playerClass = computed(() => [
  'flex w-full min-w-64 max-w-96 items-center gap-2 rounded-xl px-3 py-2 shadow-[0_1px_1px_rgba(0,0,0,0.14)]',
  isOutgoing.value
    ? 'bg-n-teal-4 text-n-slate-12'
    : 'bg-n-slate-4 text-n-slate-12',
]);
const playedBarClass = computed(() => 'bg-n-blue-9');
const pendingBarClass = computed(() =>
  isOutgoing.value ? 'bg-n-teal-8/70' : 'bg-n-slate-8'
);

const barHeightClass = value => {
  const heightMap = {
    1: 'h-0.5',
    2: 'h-1',
    3: 'h-2',
    4: 'h-3',
    5: 'h-4',
    6: 'h-5',
  };

  return heightMap[value] || 'h-2';
};

const barColorClass = index =>
  index < activeBarCount.value ? playedBarClass.value : pendingBarClass.value;

onMounted(() => {
  const d = audioPlayer.value?.duration;
  setDuration(d);
  if (metaDuration.value && !duration.value)
    duration.value = metaDuration.value;
  if (audioPlayer.value) audioPlayer.value.playbackRate = playbackSpeed.value;
});

useEmitter('pause_playing_audio', currentPlayingId => {
  if (currentPlayingId !== uid && isPlaying.value) {
    try {
      audioPlayer.value.pause();
    } catch {
      // Ignore pause errors from detached audio elements.
    }
    isPlaying.value = false;
  }
});

const onTimeUpdate = () => {
  currentTime.value = audioPlayer.value?.currentTime || 0;
};

const seek = event => {
  const time = Number(event.target.value);
  audioPlayer.value.currentTime = time;
  currentTime.value = time;
};

const playOrPause = async () => {
  if (!audioPlayer.value || !hasPlayableSource.value) return;

  if (isPlaying.value) {
    audioPlayer.value.pause();
    isPlaying.value = false;
    return;
  }

  emitter.emit('pause_playing_audio', uid);
  try {
    await audioPlayer.value.play();
    syncDuration();
    isPlaying.value = true;
  } catch {
    isPlaying.value = false;
  }
};

const onEnd = () => {
  isPlaying.value = false;
  currentTime.value = 0;
  playbackSpeed.value = 1;
  audioPlayer.value.playbackRate = 1;
};

const changePlaybackSpeed = () => {
  const speeds = [1, 1.5, 2];
  const currentIndex = speeds.indexOf(playbackSpeed.value);
  const nextIndex = (currentIndex + 1) % speeds.length;
  playbackSpeed.value = speeds[nextIndex];
  audioPlayer.value.playbackRate = playbackSpeed.value;
};
</script>

<template>
  <audio
    ref="audioPlayer"
    class="hidden"
    playsinline
    preload="metadata"
    :src="timeStampURL"
    @loadedmetadata="onLoadedMetadata"
    @loadeddata="syncDuration"
    @durationchange="syncDuration"
    @canplay="syncDuration"
    @timeupdate="onTimeUpdate"
    @ended="onEnd"
  />
  <div v-bind="$attrs" class="flex w-full max-w-96 flex-col gap-2">
    <div :class="playerClass">
      <div v-if="isRecordedAudio && isOutgoing" class="relative shrink-0">
        <Avatar :name="avatarName" :src="avatarSrc" :size="44" />
        <span
          class="absolute -bottom-0.5 -right-0.5 grid size-4 place-items-center rounded-full bg-n-teal-9 text-white"
        >
          <Icon class="size-2.5" icon="i-lucide-mic" />
        </span>
      </div>

      <div
        v-else-if="!isRecordedAudio"
        class="grid size-11 shrink-0 place-items-center rounded-full bg-n-amber-9 text-n-amber-12"
      >
        <Icon class="size-6" icon="i-lucide-headphones" />
      </div>

      <button
        v-if="isPlaying"
        class="grid h-6 min-w-11 place-items-center rounded-full border-0 bg-n-alpha-black2 px-2 text-xs font-semibold text-n-slate-12"
        @click="changePlaybackSpeed"
      >
        {{ playbackSpeedLabel }}
      </button>

      <button
        class="grid size-8 shrink-0 place-items-center border-0 p-0 text-n-slate-12"
        :class="{ 'cursor-not-allowed opacity-50': !hasPlayableSource }"
        :disabled="!hasPlayableSource"
        @click="playOrPause"
      >
        <Icon
          v-if="isPlaying"
          class="size-8"
          icon="i-teenyicons-pause-small-solid"
        />
        <Icon v-else class="size-8" icon="i-teenyicons-play-small-solid" />
      </button>

      <div class="flex min-w-0 flex-1 flex-col justify-center gap-0.5">
        <div class="relative flex h-5 min-w-32 items-center">
          <div class="flex h-5 w-full items-center gap-0.5">
            <span
              v-for="(height, index) in waveformBars"
              :key="`${height}-${index}`"
              class="w-0.5 shrink-0 rounded-full"
              :class="[barHeightClass(height), barColorClass(index)]"
            />
          </div>
          <input
            type="range"
            min="0"
            :max="effectiveDuration"
            :value="currentTime"
            class="absolute inset-0 h-full w-full cursor-pointer opacity-0"
            @input="seek"
          />
        </div>
        <span
          class="tabular-nums text-[11px] font-medium leading-none text-n-slate-11"
        >
          {{ displayTime }}
        </span>
      </div>

      <div v-if="isRecordedAudio && !isOutgoing" class="relative shrink-0">
        <Avatar :name="avatarName" :src="avatarSrc" :size="44" />
        <span
          class="absolute -bottom-0.5 -left-0.5 grid size-4 place-items-center rounded-full bg-n-teal-9 text-white"
        >
          <Icon class="size-2.5" icon="i-lucide-mic" />
        </span>
      </div>
    </div>

    <div
      v-if="props.attachment.transcribedText && props.showTranscribedText"
      class="w-full rounded-lg bg-n-alpha-1 p-3 text-sm text-n-slate-12 break-words"
    >
      {{ displayedTranscript }}
      <button
        v-if="isTranscriptLong"
        class="mt-1 block border-0 bg-transparent p-0 font-medium text-n-slate-11 hover:text-n-slate-12"
        @click="isTranscriptExpanded = !isTranscriptExpanded"
      >
        {{
          isTranscriptExpanded
            ? $t('CONVERSATION.VOICE_CALL.TRANSCRIPT_SHOW_LESS')
            : $t('CONVERSATION.VOICE_CALL.TRANSCRIPT_SHOW_MORE')
        }}
      </button>
    </div>
  </div>
</template>
