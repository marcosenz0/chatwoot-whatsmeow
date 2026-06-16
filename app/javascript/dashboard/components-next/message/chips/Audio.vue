<script setup>
import {
  computed,
  getCurrentInstance,
  onMounted,
  ref,
  useTemplateRef,
  watch,
} from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { timeStampAppendedURL } from 'dashboard/helper/URLHelper';
import { useAlert } from 'dashboard/composables';
import { useEmitter } from 'dashboard/composables/emitter';
import { emitter } from 'shared/helpers/mitt';
import { LocalStorage } from 'shared/helpers/localStorage';
import MessageMeta from '../MessageMeta.vue';
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
  showMessageMeta: {
    type: Boolean,
    default: false,
  },
});

defineOptions({
  inheritAttrs: false,
});

const { contentAttributes, conversationId, id, orientation, sender } =
  useMessageContext();
const store = useStore();
const { t } = useI18n();

const timeStampURL = computed(() => {
  if (!props.attachment.dataUrl) return '';
  return timeStampAppendedURL(props.attachment.dataUrl);
});

const audioMeta = computed(() => props.attachment.meta || {});

const getAttachmentText = (...keys) => {
  const value = keys
    .map(key => props.attachment[key] ?? audioMeta.value[key])
    .find(text => typeof text === 'string' && text.trim());

  return value || '';
};

const transcriptText = computed(() =>
  getAttachmentText('transcribedText', 'transcribed_text')
);
const summaryText = computed(() =>
  getAttachmentText('summaryText', 'summary_text')
);
const AUDIO_TEXT_PREVIEW_LENGTH = 200;
const isTranscriptExpanded = ref(false);
const isSummaryExpanded = ref(false);
const showTranscript = ref(Boolean(transcriptText.value));
const showSummary = ref(Boolean(summaryText.value));
const isTranscribing = ref(false);
const isSummarizing = ref(false);
const isTranscriptLong = computed(
  () => transcriptText.value.length > AUDIO_TEXT_PREVIEW_LENGTH
);
const isSummaryLong = computed(
  () => summaryText.value.length > AUDIO_TEXT_PREVIEW_LENGTH
);
const displayedTranscript = computed(() => {
  if (!isTranscriptLong.value || isTranscriptExpanded.value)
    return transcriptText.value;
  return `${transcriptText.value
    .slice(0, AUDIO_TEXT_PREVIEW_LENGTH)
    .trimEnd()}...`;
});
const displayedSummary = computed(() => {
  if (!isSummaryLong.value || isSummaryExpanded.value) return summaryText.value;
  return `${summaryText.value
    .slice(0, AUDIO_TEXT_PREVIEW_LENGTH)
    .trimEnd()}...`;
});

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

const PLAYED_AUDIO_STORE = 'chatwoot:played-audio-attachments';
const audioPlayedKey = computed(() =>
  String(props.attachment.id || props.attachment.dataUrl || '')
);
const wasAudioPlayed = () =>
  audioPlayedKey.value
    ? Boolean(
        LocalStorage.getFromJsonStore(PLAYED_AUDIO_STORE, audioPlayedKey.value)
      )
    : false;
const isAudioHeard = ref(wasAudioPlayed());
const isUnheardIncomingRecordedAudio = computed(
  () => isRecordedAudio.value && !isOutgoing.value && !isAudioHeard.value
);

const markAudioAsHeard = () => {
  if (!audioPlayedKey.value || isAudioHeard.value) return;

  LocalStorage.updateJsonStore(PLAYED_AUDIO_STORE, audioPlayedKey.value, true);
  isAudioHeard.value = true;
};

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
const generatedWaveform = ref([]);
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
const WAVEFORM_BAR_COUNT = 48;
const FLAT_WAVEFORM = Array.from({ length: WAVEFORM_BAR_COUNT }, () => 1);

const clampWaveformHeight = value =>
  Math.max(1, Math.min(6, Math.round(Number(value) || 1)));

const resampleWaveform = values => {
  if (!values.length) return [];

  return Array.from({ length: WAVEFORM_BAR_COUNT }, (_, index) => {
    if (values.length === 1) return values[0];

    const sourceIndex = Math.round(
      (index / (WAVEFORM_BAR_COUNT - 1)) * (values.length - 1)
    );
    return values[sourceIndex];
  });
};

const normalizeWaveform = values => {
  const heights = resampleWaveform(values.map(clampWaveformHeight));
  const maxHeight = Math.max(...heights, 1);

  if (maxHeight >= 5) return heights;

  return heights.map(value =>
    clampWaveformHeight(Math.max(1, (value / maxHeight) * 6))
  );
};

const decodedWaveform = computed(() => {
  const rawWaveform = audioMeta.value.waveform;
  if (Array.isArray(rawWaveform)) {
    return normalizeWaveform(rawWaveform);
  }
  if (!rawWaveform || typeof rawWaveform !== 'string') return [];

  try {
    const binary = atob(rawWaveform);
    const heights = Array.from(binary).map(value =>
      clampWaveformHeight((value.charCodeAt(0) / 255) * 6)
    );
    return normalizeWaveform(heights);
  } catch {
    return [];
  }
});

const generateWaveformFromBuffer = audioBuffer => {
  const channelData = audioBuffer.getChannelData(0);
  const samplesPerBar = Math.max(
    1,
    Math.floor(channelData.length / WAVEFORM_BAR_COUNT)
  );
  const amplitudes = Array.from({ length: WAVEFORM_BAR_COUNT }, (_, index) => {
    const start = index * samplesPerBar;
    const end =
      index === WAVEFORM_BAR_COUNT - 1
        ? channelData.length
        : Math.min(channelData.length, start + samplesPerBar);
    let peak = 0;

    for (let sampleIndex = start; sampleIndex < end; sampleIndex += 1) {
      peak = Math.max(peak, Math.abs(channelData[sampleIndex]));
    }

    return peak;
  });

  const maxAmplitude = Math.max(...amplitudes, 0);
  if (maxAmplitude <= 0.005) return FLAT_WAVEFORM;

  return amplitudes.map(amplitude =>
    clampWaveformHeight((amplitude / maxAmplitude) * 6)
  );
};

const generateWaveformFromAudio = async () => {
  if (!timeStampURL.value || !isRecordedAudio.value) return;

  try {
    const response = await fetch(timeStampURL.value, {
      credentials: 'include',
    });
    if (!response.ok) return;

    const audioData = await response.arrayBuffer();
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return;

    const audioContext = new AudioContext();
    const audioBuffer = await audioContext.decodeAudioData(audioData);
    generatedWaveform.value = generateWaveformFromBuffer(audioBuffer);
    setDuration(audioBuffer.duration);
    await audioContext.close();
  } catch {
    generatedWaveform.value = [];
  }
};

const waveformBars = computed(() => {
  if (!isRecordedAudio.value) return FLAT_WAVEFORM;
  if (generatedWaveform.value.length) return generatedWaveform.value;
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
const playerToneClass = computed(() => {
  if (isUnheardIncomingRecordedAudio.value || isOutgoing.value) {
    return 'bg-n-teal-4 text-n-slate-12';
  }

  return 'bg-n-slate-4 text-n-slate-12';
});
const playerClass = computed(() => [
  'flex w-full min-w-80 max-w-[28rem] items-center gap-2 rounded-xl px-3 py-2 shadow-[0_1px_1px_rgba(0,0,0,0.14)]',
  playerToneClass.value,
]);
const playedBarClass = computed(() =>
  isUnheardIncomingRecordedAudio.value ? 'bg-n-teal-9' : 'bg-n-blue-9'
);
const pendingBarClass = computed(() => {
  if (isUnheardIncomingRecordedAudio.value || isOutgoing.value) {
    return 'bg-n-teal-8/70';
  }

  return 'bg-n-slate-8';
});
const micBadgeClass = computed(() =>
  isUnheardIncomingRecordedAudio.value ? 'bg-n-teal-9' : 'bg-n-blue-9'
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

const canProcessAudio = computed(() =>
  Boolean(conversationId.value && id.value && props.attachment.id)
);
const showAudioActions = computed(
  () => props.showTranscribedText && Boolean(props.attachment.id)
);
const transcribeButtonLabel = computed(() => {
  if (isTranscribing.value) return t('CONVERSATION.AUDIO.TRANSCRIBING');
  if (showTranscript.value && transcriptText.value)
    return t('CONVERSATION.AUDIO.HIDE_TRANSCRIPT');

  return t('CONVERSATION.AUDIO.TRANSCRIBE');
});
const summarizeButtonLabel = computed(() => {
  if (isSummarizing.value) return t('CONVERSATION.AUDIO.SUMMARIZING');
  if (showSummary.value && summaryText.value)
    return t('CONVERSATION.AUDIO.HIDE_SUMMARY');

  return t('CONVERSATION.AUDIO.SUMMARIZE');
});

const audioProcessingError = error =>
  error?.response?.data?.error || t('CONVERSATION.AUDIO.PROCESSING_ERROR');

const transcribeAudio = async () => {
  if (transcriptText.value) {
    showTranscript.value = !showTranscript.value;
    return;
  }

  if (!canProcessAudio.value || isTranscribing.value) return;

  isTranscribing.value = true;
  try {
    await store.dispatch('transcribeAudioMessage', {
      conversationId: conversationId.value,
      messageId: id.value,
      attachmentId: props.attachment.id,
    });
    showTranscript.value = true;
  } catch (error) {
    useAlert(audioProcessingError(error));
  } finally {
    isTranscribing.value = false;
  }
};

const summarizeAudio = async () => {
  if (summaryText.value) {
    showSummary.value = !showSummary.value;
    return;
  }

  if (!canProcessAudio.value || isSummarizing.value) return;

  isSummarizing.value = true;
  try {
    await store.dispatch('summarizeAudioMessage', {
      conversationId: conversationId.value,
      messageId: id.value,
      attachmentId: props.attachment.id,
    });
    showSummary.value = true;
  } catch (error) {
    useAlert(audioProcessingError(error));
  } finally {
    isSummarizing.value = false;
  }
};

onMounted(() => {
  const d = audioPlayer.value?.duration;
  setDuration(d);
  if (metaDuration.value && !duration.value)
    duration.value = metaDuration.value;
  if (audioPlayer.value) audioPlayer.value.playbackRate = playbackSpeed.value;
  generateWaveformFromAudio();
});

watch(timeStampURL, () => {
  generatedWaveform.value = [];
  generateWaveformFromAudio();
});

watch(audioPlayedKey, () => {
  isAudioHeard.value = wasAudioPlayed();
});

watch(
  () => props.attachment.id,
  () => {
    isTranscriptExpanded.value = false;
    isSummaryExpanded.value = false;
    showTranscript.value = Boolean(transcriptText.value);
    showSummary.value = Boolean(summaryText.value);
  }
);

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
    if (!audioPlayer.value.readyState) audioPlayer.value.load();
    await audioPlayer.value.play();
    markAudioAsHeard();
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
    :src="timeStampURL"
    playsinline
    preload="metadata"
    @loadedmetadata="onLoadedMetadata"
    @loadeddata="syncDuration"
    @durationchange="syncDuration"
    @canplay="syncDuration"
    @timeupdate="onTimeUpdate"
    @ended="onEnd"
  />
  <div v-bind="$attrs" class="flex w-full max-w-[28rem] flex-col gap-2">
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

      <div class="flex min-w-0 flex-1 flex-col justify-center gap-1">
        <div class="relative flex h-6 min-w-0 items-center">
          <div class="flex h-6 w-full min-w-0 items-center gap-px">
            <span
              v-for="(height, index) in waveformBars"
              :key="`${height}-${index}`"
              class="min-w-px flex-1 rounded-full"
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
        <div class="flex min-w-0 items-center gap-2 leading-none">
          <span
            class="tabular-nums text-[11px] font-medium leading-none text-n-slate-11"
          >
            {{ displayTime }}
          </span>
          <MessageMeta
            v-if="props.showMessageMeta"
            class="ml-auto justify-end text-[10px] font-medium leading-none text-n-slate-11"
          />
        </div>
      </div>

      <div v-if="isRecordedAudio && !isOutgoing" class="relative shrink-0">
        <Avatar :name="avatarName" :src="avatarSrc" :size="44" />
        <span
          class="absolute -bottom-0.5 -left-0.5 grid size-4 place-items-center rounded-full text-white"
          :class="micBadgeClass"
        >
          <Icon class="size-2.5" icon="i-lucide-mic" />
        </span>
      </div>
    </div>

    <div v-if="showAudioActions" class="flex flex-wrap items-center gap-2 px-1">
      <Button
        :label="transcribeButtonLabel"
        :is-loading="isTranscribing"
        :disabled="isSummarizing || !canProcessAudio"
        icon="i-lucide-file-text"
        slate
        faded
        xs
        @click="transcribeAudio"
      />
      <Button
        :label="summarizeButtonLabel"
        :is-loading="isSummarizing"
        :disabled="isTranscribing || !canProcessAudio"
        icon="i-lucide-sparkles"
        blue
        faded
        xs
        @click="summarizeAudio"
      />
    </div>

    <div
      v-if="showTranscript && transcriptText && props.showTranscribedText"
      class="w-full rounded-lg bg-n-alpha-1 p-3 text-sm text-n-slate-12 break-words"
    >
      <div
        class="mb-1 flex items-center gap-1 text-xs font-semibold text-n-slate-11"
      >
        <Icon class="size-3" icon="i-lucide-file-text" />
        {{ $t('CONVERSATION.AUDIO.TRANSCRIPT_TITLE') }}
      </div>
      <p class="whitespace-pre-wrap">
        {{ displayedTranscript }}
      </p>
      <button
        v-if="isTranscriptLong"
        class="mt-1 block border-0 bg-transparent p-0 font-medium text-n-slate-11 hover:text-n-slate-12"
        @click="isTranscriptExpanded = !isTranscriptExpanded"
      >
        {{
          isTranscriptExpanded
            ? $t('CONVERSATION.SHOW_LESS')
            : $t('CONVERSATION.SHOW_MORE')
        }}
      </button>
    </div>

    <div
      v-if="showSummary && summaryText && props.showTranscribedText"
      class="w-full rounded-lg bg-n-blue-9/10 p-3 text-sm text-n-slate-12 break-words"
    >
      <div
        class="mb-1 flex items-center gap-1 text-xs font-semibold text-n-blue-11"
      >
        <Icon class="size-3" icon="i-lucide-sparkles" />
        {{ $t('CONVERSATION.AUDIO.SUMMARY_TITLE') }}
      </div>
      <p class="whitespace-pre-wrap">
        {{ displayedSummary }}
      </p>
      <button
        v-if="isSummaryLong"
        class="mt-1 block border-0 bg-transparent p-0 font-medium text-n-slate-11 hover:text-n-slate-12"
        @click="isSummaryExpanded = !isSummaryExpanded"
      >
        {{
          isSummaryExpanded
            ? $t('CONVERSATION.SHOW_LESS')
            : $t('CONVERSATION.SHOW_MORE')
        }}
      </button>
    </div>
  </div>
</template>
