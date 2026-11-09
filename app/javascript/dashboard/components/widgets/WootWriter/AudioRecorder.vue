<script setup>
import getUuid from 'widget/helpers/uuid';
import { ref, onMounted, onBeforeUnmount } from 'vue';
import WaveSurfer from 'wavesurfer.js';
import RecordPlugin from 'wavesurfer.js/dist/plugins/record.js';
import { format, intervalToDuration } from 'date-fns';
import { convertAudio } from './utils/audioConversionUtils';

const props = defineProps({
  audioRecordFormat: {
    type: String,
    required: true,
  },
});

const emit = defineEmits([
  'recorderProgressChanged',
  'recordStarted',
  'finishRecord',
  'pause',
  'play',
  'recordError',
]);

const waveformContainer = ref(null);
let wavesurfer;
let record;
let isStarting = true;
let discarded = false;
let recordedAudioUrl;

const formatTimeProgress = time => {
  const duration = intervalToDuration({ start: 0, end: time });
  return format(
    new Date(0, 0, 0, 0, duration.minutes, duration.seconds),
    'mm:ss'
  );
};

const AUDIO_EXTENSION_MAP = {
  'audio/ogg': 'ogg',
  'audio/mp3': 'mp3',
  'audio/mpeg': 'mp3',
  'audio/wav': 'wav',
  'audio/webm': 'webm',
};

const getRecordPluginOptions = audioFormat => {
  const options = {
    scrollingWaveform: true,
    renderRecordedAudio: false,
  };
  if (
    audioFormat === 'audio/ogg' &&
    MediaRecorder.isTypeSupported('audio/ogg;codecs=opus')
  ) {
    options.mimeType = 'audio/ogg;codecs=opus';
  }
  return options;
};

const initWaveSurfer = () => {
  wavesurfer = WaveSurfer.create({
    container: waveformContainer.value,
    waveColor: '#1F93FF',
    progressColor: '#6E6F73',
    height: 100,
    barWidth: 2,
    barGap: 1,
    barRadius: 2,
    plugins: [
      RecordPlugin.create(getRecordPluginOptions(props.audioRecordFormat)),
    ],
  });

  [record] = wavesurfer.plugins;

  record.on('record-end', async blob => {
    if (discarded) return;

    try {
      const audioBlob = await convertAudio(blob, props.audioRecordFormat);
      if (discarded) return;
      if (!audioBlob.size) throw new Error('Empty recording');
      // Use the converted blob's actual type, which may differ from the
      // requested format when the browser can't produce it (e.g. Safari falls
      // back to MP3 instead of OGG). This keeps the filename, content type, and
      // voice-note flag consistent with the real bytes.
      const audioType =
        audioBlob.type.split(';')[0].trim() || props.audioRecordFormat;
      const ext = AUDIO_EXTENSION_MAP[audioType] || 'mp3';
      const fileName = `${getUuid()}.${ext}`;
      const file = new File([audioBlob], fileName, {
        type: audioType,
      });
      recordedAudioUrl = URL.createObjectURL(audioBlob);
      await wavesurfer.load(recordedAudioUrl);
      if (discarded) return;

      wavesurfer.on('pause', () => emit('pause'));
      wavesurfer.on('play', () => emit('play'));
      wavesurfer.on('finish', () => emit('pause'));
      emit('finishRecord', {
        name: file.name,
        type: file.type,
        size: file.size,
        file,
      });
    } catch (error) {
      if (!discarded) emit('recordError', { error });
    }
  });

  record.on('record-progress', time => {
    if (!discarded) emit('recorderProgressChanged', formatTimeProgress(time));
  });
};

const stopRecording = () => record.stopRecording();
const playPause = () => wavesurfer.playPause();

const discardRecording = () => {
  discarded = true;
  // startMic can still resolve after cancellation. Destroy the plugin once it
  // owns the stream so that it also releases a late microphone permission.
  if (isStarting) return;

  wavesurfer?.destroy();
  wavesurfer = null;
  if (recordedAudioUrl) {
    URL.revokeObjectURL(recordedAudioUrl);
    recordedAudioUrl = null;
  }
};

onMounted(async () => {
  try {
    initWaveSurfer();
    await record.startMic();
    if (discarded) return;

    await record.startRecording();
    if (!discarded) emit('recordStarted');
  } catch (error) {
    if (!discarded) emit('recordError', { error });
  } finally {
    isStarting = false;
    if (discarded) discardRecording();
  }
});

onBeforeUnmount(discardRecording);

defineExpose({ playPause, stopRecording, discardRecording });
</script>

<template>
  <div ref="waveformContainer" class="w-full p-1" />
</template>
