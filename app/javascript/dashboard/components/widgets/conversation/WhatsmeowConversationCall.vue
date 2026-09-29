<script setup>
/* global VideoFrame, VideoEncoder, VideoDecoder, EncodedVideoChunk */
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import whatsmeowCalls from 'dashboard/api/whatsmeowCalls';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
  chat: { type: Object, default: () => ({}) },
  contact: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const isDirectWhatsmeow = computed(
  () =>
    props.inbox?.channel_type === 'Channel::Whatsmeow' &&
    props.chat?.whatsmeow_call_available === true
);
const state = ref('idle');
const busy = ref(false);
const muted = ref(false);
const cameraOn = ref(false);
const remoteVideoOn = ref(false);
const videoCall = ref(false);
const inviteOpen = ref(false);
const participantPhone = ref('');
const connectedAt = ref(null);
const elapsedSeconds = ref(0);
const localVideo = ref(null);
const remoteCanvas = ref(null);
const devices = ref([]);
const selectedMicrophoneId = ref('default');
const selectedSpeakerId = ref('default');
const selectedCameraId = ref('default');
const audioDevicesOpen = ref(false);
const cameraDevicesOpen = ref(false);
let socket;
let socketConversationId;
let openingSocket;
let reconnectTimer;
let audioContext;
let microphone;
let microphoneSource;
let audioProcessor;
let captureProgress = 0;
let captureBuffer = [];
let nextPlaybackTime = 0;
let camera;
let videoFrameTimer;
let videoEncoder;
let videoDecoder;
let videoDecodeStarted = false;
let forceKeyframe = false;
let frameCount = 0;
let callId;
let durationTimer;

const isInCall = computed(() =>
  ['connecting', 'dialing', 'answering', 'connected'].includes(state.value)
);
const showPanel = computed(() => state.value !== 'idle');
const contactName = computed(
  () =>
    props.contact?.name ||
    props.chat?.meta?.sender?.name ||
    props.contact?.phone_number ||
    t('CONVERSATION.WHATSMEOW_CALL.TITLE')
);
const contactPhone = computed(
  () =>
    props.contact?.phone_number || props.chat?.meta?.sender?.phone_number || ''
);
const contactAvatar = computed(
  () => props.contact?.thumbnail || props.chat?.meta?.sender?.thumbnail || ''
);
const elapsedTime = computed(
  () =>
    `${String(Math.floor(elapsedSeconds.value / 60)).padStart(2, '0')}:${String(elapsedSeconds.value % 60).padStart(2, '0')}`
);
const deviceChoices = kind => [
  {
    deviceId: 'default',
    label: t('CONVERSATION.WHATSMEOW_CALL.DEFAULT_DEVICE'),
  },
  ...devices.value.filter(
    device => device.kind === kind && device.deviceId !== 'default'
  ),
];
const microphones = computed(() => deviceChoices('audioinput'));
const speakers = computed(() => deviceChoices('audiooutput'));
const cameras = computed(() => deviceChoices('videoinput'));
const deviceName = (device, index, kind) =>
  device.label || `${t(`CONVERSATION.WHATSMEOW_CALL.${kind}`)} ${index + 1}`;
const loadDevices = async () => {
  devices.value = await navigator.mediaDevices.enumerateDevices();
};
const statusText = computed(() => {
  switch (state.value) {
    case 'incoming':
      return t('CONVERSATION.WHATSMEOW_CALL.INCOMING');
    case 'dialing':
      return t('CONVERSATION.WHATSMEOW_CALL.DIALING');
    case 'answering':
      return t('CONVERSATION.WHATSMEOW_CALL.ANSWERING');
    case 'connected':
      return t('CONVERSATION.WHATSMEOW_CALL.CONNECTED');
    default:
      return t('CONVERSATION.WHATSMEOW_CALL.CONNECTING');
  }
});

const sendCommand = (action, target) => {
  if (socket?.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify({ action, target }));
  }
};

const sendMedia = (kind, bytes) => {
  if (socket?.readyState !== WebSocket.OPEN || socket.bufferedAmount > 512000) {
    return;
  }
  const packet = new Uint8Array(bytes.byteLength + 1);
  packet[0] = kind;
  packet.set(bytes, 1);
  socket.send(packet);
};

const stopMicrophone = async () => {
  const processor = audioProcessor;
  const source = microphoneSource;
  const stream = microphone;
  const context = audioContext;
  audioProcessor = null;
  microphoneSource = null;
  microphone = null;
  audioContext = null;
  captureBuffer = [];
  captureProgress = 0;
  nextPlaybackTime = 0;
  processor?.disconnect();
  source?.disconnect();
  stream?.getTracks().forEach(track => track.stop());
  if (context && context.state !== 'closed') await context.close();
};

const startMicrophone = async () => {
  if (microphone) return;
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      echoCancellation: true,
      noiseSuppression: true,
      ...(selectedMicrophoneId.value !== 'default' && {
        deviceId: { exact: selectedMicrophoneId.value },
      }),
    },
  });
  if (state.value === 'idle') {
    stream.getTracks().forEach(track => track.stop());
    return;
  }
  microphone = stream;
  audioContext = new AudioContext({ sampleRate: 16000 });
  if (selectedSpeakerId.value !== 'default') {
    await audioContext.setSinkId(selectedSpeakerId.value);
  }
  await audioContext.resume();
  microphoneSource = audioContext.createMediaStreamSource(microphone);
  audioProcessor = audioContext.createScriptProcessor(1024, 1, 1);
  audioProcessor.onaudioprocess = event => {
    event.outputBuffer.getChannelData(0).fill(0);
    if (muted.value) return;
    const input = event.inputBuffer.getChannelData(0);
    const ratio = 16000 / audioContext.sampleRate;
    input.forEach(sample => {
      captureProgress += ratio;
      if (captureProgress >= 1) {
        captureProgress -= 1;
        captureBuffer.push(sample);
        if (captureBuffer.length === 960) {
          const pcm = new Int16Array(960);
          captureBuffer.forEach((value, index) => {
            pcm[index] = Math.max(-32768, Math.min(32767, value * 32768));
          });
          captureBuffer = [];
          sendMedia(1, new Uint8Array(pcm.buffer));
        }
      }
    });
  };
  microphoneSource.connect(audioProcessor);
  audioProcessor.connect(audioContext.destination);
  await loadDevices();
};

const selectMicrophone = async deviceId => {
  audioDevicesOpen.value = false;
  if (deviceId === selectedMicrophoneId.value) return;
  try {
    if (microphone) {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          ...(deviceId !== 'default' && { deviceId: { exact: deviceId } }),
        },
      });
      const source = audioContext.createMediaStreamSource(stream);
      source.connect(audioProcessor);
      microphoneSource?.disconnect();
      microphone?.getTracks().forEach(track => track.stop());
      microphone = stream;
      microphoneSource = source;
    }
    selectedMicrophoneId.value = deviceId;
    await loadDevices();
  } catch (error) {
    useAlert(error.message);
  }
};

const selectSpeaker = async deviceId => {
  audioDevicesOpen.value = false;
  if (deviceId === selectedSpeakerId.value) return;
  try {
    if (audioContext) {
      if (!audioContext.setSinkId) {
        throw new Error(t('CONVERSATION.WHATSMEOW_CALL.OUTPUT_UNSUPPORTED'));
      }
      await audioContext.setSinkId(deviceId);
    }
    selectedSpeakerId.value = deviceId;
  } catch (error) {
    useAlert(error.message);
  }
};

const playAudio = bytes => {
  if (!audioContext || bytes.byteLength !== 1920) return;
  const pcm = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const buffer = audioContext.createBuffer(1, 960, 16000);
  const samples = buffer.getChannelData(0);
  for (let i = 0; i < 960; i += 1) {
    samples[i] = pcm.getInt16(i * 2, true) / 32768;
  }
  const source = audioContext.createBufferSource();
  source.buffer = buffer;
  source.connect(audioContext.destination);
  if (nextPlaybackTime > audioContext.currentTime + 0.3) {
    nextPlaybackTime = audioContext.currentTime + 0.03;
  }
  nextPlaybackTime = Math.max(
    audioContext.currentTime + 0.03,
    nextPlaybackTime
  );
  source.start(nextPlaybackTime);
  nextPlaybackTime += 0.06;
};

const stopCamera = async () => {
  clearInterval(videoFrameTimer);
  videoFrameTimer = null;
  if (videoEncoder && videoEncoder.state !== 'closed') videoEncoder.close();
  videoEncoder = null;
  camera?.getTracks().forEach(track => track.stop());
  camera = null;
  if (localVideo.value) localVideo.value.srcObject = null;
  cameraOn.value = false;
};

const pumpCamera = encoder => {
  let encodedWidth = 0;
  let encodedHeight = 0;
  videoFrameTimer = setInterval(() => {
    const video = localVideo.value;
    if (!video || video.readyState < 2 || encoder.encodeQueueSize >= 2) return;
    try {
      const frame = new VideoFrame(video, {
        timestamp: Math.round(performance.now() * 1000),
      });
      const width = frame.displayWidth;
      const height = frame.displayHeight;
      if (width !== encodedWidth || height !== encodedHeight) {
        encodedWidth = width;
        encodedHeight = height;
        encoder.configure({
          codec: 'avc1.42E01F',
          avc: { format: 'annexb' },
          width,
          height,
          framerate: 15,
          bitrate: Math.max(250000, Math.min(2000000, width * height * 2)),
          latencyMode: 'realtime',
        });
        forceKeyframe = true;
      }
      if (encoder.state === 'configured') {
        const keyFrame = forceKeyframe || frameCount % 15 === 0;
        forceKeyframe = false;
        frameCount += 1;
        encoder.encode(frame, { keyFrame });
      }
      frame.close();
    } catch (error) {
      useAlert(error.message);
      stopCamera();
    }
  }, 1000 / 15);
};

const startCamera = async () => {
  if (camera) return;
  if (
    typeof VideoFrame === 'undefined' ||
    typeof VideoEncoder === 'undefined'
  ) {
    throw new Error(t('CONVERSATION.WHATSMEOW_CALL.VIDEO_UNSUPPORTED'));
  }
  const stream = await navigator.mediaDevices.getUserMedia({
    video: {
      width: { ideal: 640, max: 1280 },
      height: { ideal: 480, max: 720 },
      frameRate: 15,
      ...(selectedCameraId.value !== 'default' && {
        deviceId: { exact: selectedCameraId.value },
      }),
    },
  });
  if (state.value === 'idle') {
    stream.getTracks().forEach(track => track.stop());
    return;
  }
  camera = stream;
  cameraOn.value = true;
  await nextTick();
  if (localVideo.value) {
    localVideo.value.srcObject = camera;
    await localVideo.value.play();
  }
  videoEncoder = new VideoEncoder({
    output: chunk => {
      const bytes = new Uint8Array(chunk.byteLength);
      chunk.copyTo(bytes);
      sendMedia(2, bytes);
    },
    error: error => useAlert(error.message),
  });
  forceKeyframe = true;
  frameCount = 0;
  pumpCamera(videoEncoder);
  await loadDevices();
};

const selectCamera = async deviceId => {
  cameraDevicesOpen.value = false;
  if (deviceId === selectedCameraId.value) return;
  const previousId = selectedCameraId.value;
  selectedCameraId.value = deviceId;
  if (!cameraOn.value) return;
  try {
    await stopCamera();
    await startCamera();
  } catch (error) {
    useAlert(error.message);
    await stopCamera();
    selectedCameraId.value = previousId;
    await startCamera().catch(restoreError => useAlert(restoreError.message));
  }
};

const isKeyFrame = bytes => {
  for (let i = 0; i + 4 < bytes.length; i += 1) {
    let offset = -1;
    if (bytes[i] === 0 && bytes[i + 1] === 0 && bytes[i + 2] === 1) {
      offset = i + 3;
    } else if (
      bytes[i] === 0 &&
      bytes[i + 1] === 0 &&
      bytes[i + 2] === 0 &&
      bytes[i + 3] === 1
    ) {
      offset = i + 4;
    }
    if (offset >= 0 && [5, 7].includes(bytes[offset] % 32)) return true;
  }
  return false;
};

const decodeVideo = bytes => {
  if (typeof VideoDecoder === 'undefined') return;
  const keyFrame = isKeyFrame(bytes);
  if (!videoDecodeStarted && !keyFrame) return;
  if (!videoDecoder || videoDecoder.state === 'closed') {
    videoDecoder = new VideoDecoder({
      output: frame => {
        const canvas = remoteCanvas.value;
        if (canvas) {
          canvas.width = frame.displayWidth;
          canvas.height = frame.displayHeight;
          canvas.getContext('2d').drawImage(frame, 0, 0);
          remoteVideoOn.value = true;
        }
        frame.close();
      },
      error: error => useAlert(error.message),
    });
    videoDecoder.configure({ codec: 'avc1.42E01F', optimizeForLatency: true });
  }
  videoDecodeStarted = true;
  videoDecoder.decode(
    new EncodedVideoChunk({
      type: keyFrame ? 'key' : 'delta',
      timestamp: performance.now() * 1000,
      data: bytes,
    })
  );
};

const resetCall = async () => {
  state.value = 'idle';
  busy.value = false;
  muted.value = false;
  remoteVideoOn.value = false;
  videoCall.value = false;
  inviteOpen.value = false;
  participantPhone.value = '';
  connectedAt.value = null;
  elapsedSeconds.value = 0;
  clearInterval(durationTimer);
  callId = null;
  if (videoDecoder && videoDecoder.state !== 'closed') videoDecoder.close();
  videoDecoder = null;
  videoDecodeStarted = false;
  await stopCamera();
  await stopMicrophone();
  audioDevicesOpen.value = false;
  cameraDevicesOpen.value = false;
};

const onSocketMessage = event => {
  if (typeof event.data !== 'string') {
    const bytes = new Uint8Array(event.data);
    if (bytes[0] === 3) playAudio(bytes.subarray(1));
    if (bytes[0] === 4) decodeVideo(bytes.subarray(1));
    return;
  }
  const update = JSON.parse(event.data);
  if (update.event === 'error') {
    useAlert(t('CONVERSATION.WHATSMEOW_CALL.FAILED'));
    if (
      !callId ||
      ['connecting', 'dialing', 'answering'].includes(state.value)
    ) {
      resetCall();
    }
    return;
  }
  if (update.event === 'incoming' && !isInCall.value) {
    callId = update.call_id;
    videoCall.value = update.video;
    state.value = 'incoming';
  } else if (update.event === 'dialing' || update.event === 'answering') {
    callId = update.call_id;
    videoCall.value = update.video;
    state.value = update.event;
  } else if (update.event === 'connected') {
    videoCall.value = update.video;
    state.value = 'connected';
    busy.value = false;
    if (!connectedAt.value) {
      connectedAt.value = Date.now();
      durationTimer = setInterval(() => {
        elapsedSeconds.value = Math.floor(
          (Date.now() - connectedAt.value) / 1000
        );
      }, 1000);
    }
  } else if (update.event === 'ended') {
    resetCall();
  } else if (update.event === 'video_state') {
    videoCall.value = update.video;
    if ([0, 6].includes(update.video_state)) remoteVideoOn.value = false;
    if ([5, 8].includes(update.video_state) && !videoCall.value) stopCamera();
  } else if (update.event === 'keyframe') {
    forceKeyframe = true;
  } else if (update.event === 'participant_invited') {
    useAlert(t('CONVERSATION.WHATSMEOW_CALL.PARTICIPANT_INVITED'));
    inviteOpen.value = false;
    participantPhone.value = '';
  }
};

const ensureSocket = async () => {
  if (
    socket?.readyState === WebSocket.OPEN &&
    socketConversationId === props.chat.id
  ) {
    return;
  }
  if (openingSocket && socketConversationId === props.chat.id) {
    await openingSocket;
    return;
  }
  const conversationId = props.chat.id;
  socketConversationId = conversationId;
  const promise = (async () => {
    const { data } = await whatsmeowCalls.createSession(conversationId);
    if (props.chat.id === conversationId || isInCall.value) {
      const url = data.url.replace(/^http/, 'ws');
      socket?.close();
      const connection = new WebSocket(url, [
        'chatwoot.calls',
        `token.${data.token}`,
      ]);
      socket = connection;
      connection.binaryType = 'arraybuffer';
      connection.onmessage = onSocketMessage;
      connection.onclose = () => {
        if (socket === connection) {
          const hadCall = isInCall.value;
          socket = null;
          resetCall();
          if (
            !hadCall &&
            isDirectWhatsmeow.value &&
            props.chat.id === conversationId
          ) {
            reconnectTimer = setTimeout(() => {
              ensureSocket().catch(() => {});
            }, 10000);
          }
        }
      };
      await new Promise((resolve, reject) => {
        connection.onopen = resolve;
        connection.onerror = () =>
          reject(new Error(t('CONVERSATION.WHATSMEOW_CALL.FAILED')));
      });
    }
  })();
  openingSocket = promise;
  try {
    await promise;
  } finally {
    if (openingSocket === promise) openingSocket = null;
  }
};

const startCall = async video => {
  if (busy.value || state.value !== 'idle') return;
  busy.value = true;
  state.value = 'connecting';
  try {
    await startMicrophone();
    if (state.value !== 'connecting') return;
    if (video) await startCamera();
    if (state.value !== 'connecting') return;
    await ensureSocket();
    if (state.value !== 'connecting') return;
    sendCommand(video ? 'dial_video' : 'dial_audio');
  } catch (error) {
    useAlert(error.message || t('CONVERSATION.WHATSMEOW_CALL.FAILED'));
    await resetCall();
  } finally {
    busy.value = false;
  }
};

const answer = async () => {
  try {
    await startMicrophone();
    sendCommand('answer');
    state.value = 'answering';
  } catch (error) {
    useAlert(error.message);
  }
};

const endCall = () => {
  sendCommand(state.value === 'incoming' ? 'reject' : 'hangup');
  resetCall();
};

const toggleCamera = async () => {
  try {
    if (cameraOn.value) {
      sendCommand('disable_video');
      await stopCamera();
    } else {
      await startCamera();
      sendCommand(videoCall.value ? 'enable_video' : 'start_video');
    }
  } catch (error) {
    useAlert(error.message);
    await stopCamera();
  }
};

const inviteParticipant = () => {
  if (!/^\+?[1-9]\d{9,14}$/.test(participantPhone.value.replace(/\D/g, ''))) {
    useAlert(t('CONVERSATION.WHATSMEOW_CALL.PARTICIPANT_PHONE'));
    return;
  }
  sendCommand('add_participant', participantPhone.value);
};

const openChat = () => {
  inviteOpen.value = false;
  document.querySelector('.ProseMirror')?.focus();
};

watch(
  [isDirectWhatsmeow, () => route.query.whatsmeowCall, () => props.chat.id],
  ([available, requested]) => {
    if (
      !available ||
      !['voice', 'video'].includes(requested) ||
      state.value !== 'idle'
    )
      return;
    router.replace({ query: { ...route.query, whatsmeowCall: undefined } });
    startCall(requested === 'video');
  },
  { immediate: true }
);

watch(
  [() => props.chat.id, isDirectWhatsmeow, isInCall],
  () => {
    if (!isInCall.value) {
      clearTimeout(reconnectTimer);
      socket?.close();
      socket = null;
      socketConversationId = null;
      resetCall();
      if (isDirectWhatsmeow.value && props.chat.id) {
        ensureSocket().catch(() => {});
      }
    }
  },
  { immediate: true }
);

onMounted(() => {
  loadDevices().catch(() => {});
  navigator.mediaDevices.addEventListener('devicechange', loadDevices);
});

onBeforeUnmount(() => {
  navigator.mediaDevices.removeEventListener('devicechange', loadDevices);
  clearTimeout(reconnectTimer);
  if (isInCall.value) sendCommand('hangup');
  socket?.close();
  resetCall();
});
</script>

<template>
  <template v-if="isDirectWhatsmeow">
    <NextButton
      v-tooltip.bottom="t('CONVERSATION.WHATSMEOW_CALL.VOICE')"
      sm
      ghost
      slate
      icon="i-lucide-phone"
      :disabled="busy || state !== 'idle'"
      @click="startCall(false)"
    />
    <NextButton
      v-tooltip.bottom="t('CONVERSATION.WHATSMEOW_CALL.VIDEO')"
      sm
      ghost
      slate
      icon="i-lucide-video"
      :disabled="busy || state !== 'idle'"
      @click="startCall(true)"
    />
  </template>
  <Teleport to="body">
    <div
      v-if="showPanel"
      class="fixed bottom-6 right-6 z-50 flex w-96 max-w-[calc(100vw-2rem)] flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-xl"
      role="dialog"
      :aria-label="t('CONVERSATION.WHATSMEOW_CALL.TITLE')"
    >
      <div class="flex items-center gap-3">
        <img
          v-if="contactAvatar"
          :src="contactAvatar"
          alt=""
          class="size-12 rounded-full object-cover"
        />
        <span
          v-else
          class="flex size-12 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-11"
          ><span class="i-lucide-user-round size-6"
        /></span>
        <div class="min-w-0 flex-1">
          <div class="truncate text-sm font-semibold text-n-slate-12">
            {{ contactName }}
          </div>
          <div v-if="contactPhone" class="truncate text-xs text-n-slate-11">
            {{ contactPhone }}
          </div>
          <div class="text-xs text-n-slate-11">
            {{ statusText
            }}<span v-if="state === 'connected'"> · {{ elapsedTime }}</span>
          </div>
        </div>
        <span
          :class="videoCall ? 'i-lucide-video' : 'i-lucide-phone'"
          class="size-5 text-n-slate-11"
        />
      </div>
      <div
        v-show="cameraOn || remoteVideoOn"
        class="relative overflow-hidden rounded-lg bg-black"
      >
        <canvas
          ref="remoteCanvas"
          class="h-44 w-full object-contain"
          :class="{ hidden: !remoteVideoOn }"
        />
        <video
          ref="localVideo"
          autoplay
          muted
          playsinline
          class="absolute bottom-2 right-2 h-20 w-28 rounded-md bg-n-slate-2 object-cover"
          :class="{ hidden: !cameraOn }"
        />
      </div>
      <form
        v-if="inviteOpen && state === 'connected'"
        class="flex items-center gap-2"
        @submit.prevent="inviteParticipant"
      >
        <input
          v-model="participantPhone"
          type="tel"
          class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-2 py-2 text-sm text-n-slate-12"
          :placeholder="t('CONVERSATION.WHATSMEOW_CALL.PARTICIPANT_PHONE')"
        />
        <button
          type="submit"
          class="rounded-lg bg-n-brand px-3 py-2 text-sm text-white"
        >
          {{ t('CONVERSATION.WHATSMEOW_CALL.INVITE') }}
        </button>
      </form>
      <div class="flex items-center justify-center gap-3">
        <button
          v-if="state === 'incoming'"
          type="button"
          class="flex h-10 w-10 items-center justify-center rounded-full bg-n-teal-9 text-white"
          :aria-label="t('CONVERSATION.WHATSMEOW_CALL.ANSWER')"
          @click="answer"
        >
          <span class="i-lucide-phone" />
        </button>
        <template v-if="isInCall && state !== 'connecting'">
          <div
            class="flex items-center rounded-full bg-n-slate-3 text-n-slate-12"
          >
            <button
              type="button"
              class="flex size-10 items-center justify-center rounded-full"
              :class="{ 'bg-n-ruby-3': muted }"
              :aria-label="t('CONVERSATION.WHATSMEOW_CALL.MUTE')"
              @click="muted = !muted"
            >
              <span :class="muted ? 'i-lucide-mic-off' : 'i-lucide-mic'" />
            </button>
            <button
              type="button"
              class="flex h-10 w-5 items-center justify-center rounded-r-full"
              :aria-label="t('CONVERSATION.WHATSMEOW_CALL.AUDIO_DEVICES')"
              :aria-expanded="audioDevicesOpen"
              @click="
                audioDevicesOpen = !audioDevicesOpen;
                cameraDevicesOpen = false;
              "
            >
              <span class="i-lucide-chevron-down size-4" />
            </button>
          </div>
          <div
            class="flex items-center rounded-full bg-n-slate-3 text-n-slate-12"
          >
            <button
              type="button"
              class="flex size-10 items-center justify-center rounded-full"
              :class="{ 'bg-n-teal-3': cameraOn }"
              :aria-label="t('CONVERSATION.WHATSMEOW_CALL.CAMERA')"
              @click="toggleCamera"
            >
              <span
                :class="cameraOn ? 'i-lucide-video-off' : 'i-lucide-video'"
              />
            </button>
            <button
              type="button"
              class="flex h-10 w-5 items-center justify-center rounded-r-full"
              :aria-label="t('CONVERSATION.WHATSMEOW_CALL.CAMERA_DEVICES')"
              :aria-expanded="cameraDevicesOpen"
              @click="
                cameraDevicesOpen = !cameraDevicesOpen;
                audioDevicesOpen = false;
              "
            >
              <span class="i-lucide-chevron-down size-4" />
            </button>
          </div>
          <button
            v-if="state === 'connected'"
            type="button"
            class="flex size-10 items-center justify-center rounded-full bg-n-slate-3 text-n-slate-12"
            :aria-label="t('CONVERSATION.WHATSMEOW_CALL.ADD_PARTICIPANT')"
            @click="inviteOpen = !inviteOpen"
          >
            <span class="i-lucide-user-round-plus" />
          </button>
          <button
            type="button"
            class="flex size-10 items-center justify-center rounded-full bg-n-slate-3 text-n-slate-12"
            :aria-label="t('CONVERSATION.WHATSMEOW_CALL.CHAT')"
            @click="openChat"
          >
            <span class="i-lucide-message-circle" />
          </button>
        </template>
        <button
          type="button"
          class="flex h-10 w-10 items-center justify-center rounded-full bg-n-ruby-9 text-white"
          :aria-label="t('CONVERSATION.WHATSMEOW_CALL.END')"
          @click="endCall"
        >
          <span class="i-lucide-phone-off" />
        </button>
      </div>
      <div
        v-if="audioDevicesOpen"
        class="absolute bottom-20 left-4 z-10 max-h-72 w-72 max-w-[calc(100vw-3rem)] overflow-y-auto rounded-xl border border-n-weak bg-n-solid-1 p-2 shadow-xl"
      >
        <div class="px-2 py-1 text-xs font-semibold text-n-slate-11">
          {{ t('CONVERSATION.WHATSMEOW_CALL.MICROPHONES') }}
        </div>
        <button
          v-for="(device, index) in microphones"
          :key="device.deviceId || `microphone-${index}`"
          type="button"
          class="flex w-full items-center gap-2 rounded-lg px-2 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
          @click="selectMicrophone(device.deviceId)"
        >
          <span
            class="size-4 shrink-0"
            :class="{
              'i-lucide-check': device.deviceId === selectedMicrophoneId,
            }"
          />
          <span class="truncate">{{
            deviceName(device, index, 'MICROPHONE')
          }}</span>
        </button>
        <div
          class="mt-2 border-t border-n-weak px-2 py-2 text-xs font-semibold text-n-slate-11"
        >
          {{ t('CONVERSATION.WHATSMEOW_CALL.SPEAKERS') }}
        </div>
        <button
          v-for="(device, index) in speakers"
          :key="device.deviceId || `speaker-${index}`"
          type="button"
          class="flex w-full items-center gap-2 rounded-lg px-2 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
          @click="selectSpeaker(device.deviceId)"
        >
          <span
            class="size-4 shrink-0"
            :class="{ 'i-lucide-check': device.deviceId === selectedSpeakerId }"
          />
          <span class="truncate">{{
            deviceName(device, index, 'SPEAKER')
          }}</span>
        </button>
      </div>
      <div
        v-if="cameraDevicesOpen"
        class="absolute bottom-20 left-4 z-10 max-h-72 w-72 max-w-[calc(100vw-3rem)] overflow-y-auto rounded-xl border border-n-weak bg-n-solid-1 p-2 shadow-xl"
      >
        <div class="px-2 py-1 text-xs font-semibold text-n-slate-11">
          {{ t('CONVERSATION.WHATSMEOW_CALL.CAMERAS') }}
        </div>
        <button
          v-for="(device, index) in cameras"
          :key="device.deviceId || `camera-${index}`"
          type="button"
          class="flex w-full items-center gap-2 rounded-lg px-2 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
          @click="selectCamera(device.deviceId)"
        >
          <span
            class="size-4 shrink-0"
            :class="{ 'i-lucide-check': device.deviceId === selectedCameraId }"
          />
          <span class="truncate">{{
            deviceName(device, index, 'CAMERA_DEVICE')
          }}</span>
        </button>
      </div>
    </div>
  </Teleport>
</template>
