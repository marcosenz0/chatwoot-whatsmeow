<script setup>
/* global MediaStreamTrackProcessor, VideoEncoder, VideoDecoder, EncodedVideoChunk */
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import whatsmeowCalls from 'dashboard/api/whatsmeowCalls';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
  chat: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
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
const videoUpgradePending = ref(false);
const videoCall = ref(false);
const localVideo = ref(null);
const remoteCanvas = ref(null);
let socket;
let socketConversationId;
let openingSocket;
let audioContext;
let microphone;
let microphoneSource;
let audioProcessor;
let captureProgress = 0;
let captureBuffer = [];
let nextPlaybackTime = 0;
let camera;
let videoReader;
let videoEncoder;
let videoDecoder;
let videoDecodeStarted = false;
let forceKeyframe = false;
let frameCount = 0;
let callId;

const isInCall = computed(() =>
  ['dialing', 'answering', 'connected'].includes(state.value)
);
const showPanel = computed(() => state.value !== 'idle');
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

const sendCommand = action => {
  if (socket?.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify({ action }));
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
  if (audioProcessor) audioProcessor.disconnect();
  if (microphoneSource) microphoneSource.disconnect();
  microphone?.getTracks().forEach(track => track.stop());
  if (audioContext) await audioContext.close();
  audioProcessor = null;
  microphoneSource = null;
  microphone = null;
  audioContext = null;
  captureBuffer = [];
  captureProgress = 0;
  nextPlaybackTime = 0;
};

const startMicrophone = async () => {
  if (microphone) return;
  microphone = await navigator.mediaDevices.getUserMedia({
    audio: { echoCancellation: true, noiseSuppression: true },
  });
  audioContext = new AudioContext({ sampleRate: 16000 });
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
  const reader = videoReader;
  videoReader = null;
  if (reader) await reader.cancel().catch(() => {});
  if (videoEncoder && videoEncoder.state !== 'closed') videoEncoder.close();
  videoEncoder = null;
  camera?.getTracks().forEach(track => track.stop());
  camera = null;
  if (localVideo.value) localVideo.value.srcObject = null;
  cameraOn.value = false;
};

const pumpCamera = async (reader, encoder) => {
  let encodedWidth = 0;
  let encodedHeight = 0;
  try {
    // eslint-disable-next-line no-restricted-syntax
    while (videoReader === reader) {
      // Camera frames are read in sequence so the encoder preserves their order.
      // eslint-disable-next-line no-await-in-loop
      const { value: frame, done } = await reader.read();
      if (done) break;
      const scale = Math.min(
        1,
        1280 / frame.displayWidth,
        720 / frame.displayHeight
      );
      const width = Math.max(
        2,
        Math.floor((frame.displayWidth * scale) / 2) * 2
      );
      const height = Math.max(
        2,
        Math.floor((frame.displayHeight * scale) / 2) * 2
      );
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
      if (encoder.state === 'configured' && encoder.encodeQueueSize < 2) {
        const keyFrame = forceKeyframe || frameCount % 15 === 0;
        forceKeyframe = false;
        frameCount += 1;
        encoder.encode(frame, { keyFrame });
      }
      frame.close();
    }
  } catch (error) {
    if (videoReader === reader) useAlert(error.message);
  }
};

const startCamera = async () => {
  if (camera) return;
  if (
    typeof MediaStreamTrackProcessor === 'undefined' ||
    typeof VideoEncoder === 'undefined'
  ) {
    throw new Error(t('CONVERSATION.WHATSMEOW_CALL.VIDEO_UNSUPPORTED'));
  }
  camera = await navigator.mediaDevices.getUserMedia({
    video: { width: { ideal: 640 }, height: { ideal: 480 }, frameRate: 15 },
  });
  cameraOn.value = true;
  await nextTick();
  if (localVideo.value) {
    localVideo.value.srcObject = camera;
    localVideo.value.play();
  }
  videoEncoder = new VideoEncoder({
    output: chunk => {
      const bytes = new Uint8Array(chunk.byteLength);
      chunk.copyTo(bytes);
      sendMedia(2, bytes);
    },
    error: error => useAlert(error.message),
  });
  videoReader = new MediaStreamTrackProcessor({
    track: camera.getVideoTracks()[0],
  }).readable.getReader();
  forceKeyframe = true;
  frameCount = 0;
  pumpCamera(videoReader, videoEncoder);
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
  videoUpgradePending.value = false;
  videoCall.value = false;
  callId = null;
  if (videoDecoder && videoDecoder.state !== 'closed') videoDecoder.close();
  videoDecoder = null;
  videoDecodeStarted = false;
  await stopCamera();
  await stopMicrophone();
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
    useAlert(update.message || t('CONVERSATION.WHATSMEOW_CALL.FAILED'));
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
  } else if (update.event === 'ended') {
    resetCall();
  } else if (update.event === 'video_state') {
    videoCall.value = update.video;
    videoUpgradePending.value = [3, 11].includes(update.video_state);
    if ([0, 6].includes(update.video_state)) remoteVideoOn.value = false;
    if ([5, 8].includes(update.video_state) && !videoCall.value) stopCamera();
  } else if (update.event === 'keyframe') {
    forceKeyframe = true;
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
        if (socket === connection) resetCall();
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
    if (video) await startCamera();
    await ensureSocket();
    sendCommand(video ? 'dial_video' : 'dial_audio');
  } catch (error) {
    useAlert(error?.response?.data?.error || error.message);
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

const acceptVideo = async () => {
  sendCommand('accept_video');
  videoUpgradePending.value = false;
};

watch(
  [() => props.chat.id, isDirectWhatsmeow],
  () => {
    if (!isInCall.value) {
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

onBeforeUnmount(() => {
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
      class="fixed bottom-6 right-6 z-50 flex w-80 flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 shadow-xl"
      role="dialog"
      :aria-label="t('CONVERSATION.WHATSMEOW_CALL.TITLE')"
    >
      <div class="flex items-center justify-between">
        <div>
          <div class="text-sm font-semibold text-n-slate-12">
            {{ t('CONVERSATION.WHATSMEOW_CALL.TITLE') }}
          </div>
          <div class="text-xs text-n-slate-11">{{ statusText }}</div>
        </div>
        <span class="i-lucide-phone text-n-slate-11" />
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
        <template v-if="isInCall">
          <button
            type="button"
            class="flex h-10 w-10 items-center justify-center rounded-full bg-n-slate-3 text-n-slate-12"
            :aria-label="t('CONVERSATION.WHATSMEOW_CALL.MUTE')"
            @click="muted = !muted"
          >
            <span :class="muted ? 'i-lucide-mic-off' : 'i-lucide-mic'" />
          </button>
          <button
            type="button"
            class="flex h-10 w-10 items-center justify-center rounded-full bg-n-slate-3 text-n-slate-12"
            :aria-label="t('CONVERSATION.WHATSMEOW_CALL.CAMERA')"
            @click="toggleCamera"
          >
            <span :class="cameraOn ? 'i-lucide-video-off' : 'i-lucide-video'" />
          </button>
          <button
            v-if="videoUpgradePending"
            type="button"
            class="rounded-lg bg-n-teal-9 px-2 py-1 text-xs text-white"
            @click="acceptVideo"
          >
            {{ t('CONVERSATION.WHATSMEOW_CALL.ACCEPT_VIDEO') }}
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
    </div>
  </Teleport>
</template>
