<script setup>
/* global VideoDecoder, EncodedVideoChunk */
import { ref, watch, onBeforeUnmount } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import {
  drawCallVideoFrame,
  isH264KeyFrame,
} from 'dashboard/helper/whatsmeowCallVideo';

const props = defineProps({
  frame: { type: Object, required: true },
  name: { type: String, required: true },
});
const emit = defineEmits(['requestKeyframe']);
const canvas = ref(null);
const recovering = ref(true);
let decoder;
let started = false;
let lastFrameAt = 0;
const orientations = new Map();
function reset() {
  if (decoder && decoder.state !== 'closed') decoder.close();
  decoder = null;
  started = false;
  orientations.clear();
  recovering.value = true;
}
function decode(frame) {
  if (typeof VideoDecoder === 'undefined' || !canvas.value) return;
  const key = isH264KeyFrame(frame.bytes);
  if (decoder?.decodeQueueSize > 6) reset();
  if (!started && !key) {
    emit('requestKeyframe');
    return;
  }
  if (!decoder) {
    decoder = new VideoDecoder({
      output: decoded => {
        try {
          if (canvas.value) {
            drawCallVideoFrame(
              canvas.value,
              decoded,
              orientations.get(decoded.timestamp) || 0
            );
            recovering.value = false;
            lastFrameAt = performance.now();
          }
        } finally {
          orientations.delete(decoded.timestamp);
          decoded.close();
        }
      },
      error: () => {
        reset();
        emit('requestKeyframe');
      },
    });
    decoder.configure({ codec: 'avc1.42E01F', optimizeForLatency: true });
  }
  const timestamp = Math.round(performance.now() * 1000);
  orientations.set(timestamp, frame.orientation);
  started = true;
  try {
    decoder.decode(
      new EncodedVideoChunk({
        type: key ? 'key' : 'delta',
        timestamp,
        data: frame.bytes,
      })
    );
  } catch {
    reset();
    emit('requestKeyframe');
  }
}
watch(() => props.frame, decode, { flush: 'post' });
useIntervalFn(() => {
  if (performance.now() - lastFrameAt > 2000) {
    recovering.value = true;
    emit('requestKeyframe');
  }
}, 1000);
onBeforeUnmount(reset);
</script>

<template>
  <div class="relative min-h-28 overflow-hidden rounded-lg bg-black">
    <canvas ref="canvas" class="h-full w-full object-contain" />
    <span
      class="absolute bottom-1 left-1 rounded bg-black/60 px-2 py-1 text-xs text-white"
    >
      {{ name }}
    </span>
    <span
      v-if="recovering"
      class="absolute right-2 top-2 i-lucide-loader-circle size-4 text-white"
      :aria-label="$t('CONVERSATION.WHATSMEOW_CALL.RECOVERING_VIDEO')"
    />
  </div>
</template>
