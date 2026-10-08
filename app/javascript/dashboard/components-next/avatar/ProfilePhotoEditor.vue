<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  shallowRef,
} from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'next/dialog/Dialog.vue';
import Button from 'next/button/Button.vue';
import { clampCrop, cropToJpeg } from 'dashboard/helper/profilePhotoCrop';

const props = defineProps({
  file: { type: Blob, required: true },
  saving: { type: Boolean, default: false },
});
const emit = defineEmits(['confirm', 'close']);
const { t } = useI18n();
const dialog = ref(null);
const canvas = ref(null);
const image = shallowRef(null);
const zoom = ref(1);
const center = ref({ x: 0, y: 0 });
const dragging = ref(false);
const error = ref(false);
const url = URL.createObjectURL(props.file);
let previousPointer;
let disposed = false;
const crop = computed(() =>
  image.value
    ? clampCrop({
        width: image.value.naturalWidth,
        height: image.value.naturalHeight,
        zoom: zoom.value,
        ...center.value,
      })
    : null
);

const draw = () => {
  if (!crop.value || !canvas.value) return;
  center.value = { x: crop.value.x, y: crop.value.y };
  const ctx = canvas.value.getContext('2d');
  const size = canvas.value.width;
  ctx.clearRect(0, 0, size, size);
  ctx.drawImage(
    image.value,
    crop.value.x - crop.value.side / 2,
    crop.value.y - crop.value.side / 2,
    crop.value.side,
    crop.value.side,
    0,
    0,
    size,
    size
  );
  // The square is sent to WhatsApp; the mask previews its circular avatar.
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, 0, size, size);
  ctx.arc(size / 2, size / 2, size / 2 - 1, 0, Math.PI * 2, true);
  ctx.fillStyle = 'rgba(0,0,0,0.65)';
  ctx.fill();
  ctx.restore();
};
const changeZoom = delta => {
  zoom.value = Math.max(1, Math.min(4, zoom.value + delta));
  draw();
};
const reset = () => {
  if (!image.value) return;
  zoom.value = 1;
  center.value = {
    x: image.value.naturalWidth / 2,
    y: image.value.naturalHeight / 2,
  };
  draw();
};
const startDrag = event => {
  if (!image.value || props.saving) return;
  event.currentTarget.setPointerCapture(event.pointerId);
  previousPointer = { x: event.clientX, y: event.clientY };
  dragging.value = true;
};
const move = event => {
  if (!dragging.value) return;
  const scale = crop.value.side / canvas.value.getBoundingClientRect().width;
  center.value = {
    x: center.value.x - (event.clientX - previousPointer.x) * scale,
    y: center.value.y - (event.clientY - previousPointer.y) * scale,
  };
  previousPointer = { x: event.clientX, y: event.clientY };
  draw();
};
const panWithKeyboard = event => {
  if (!crop.value || props.saving) return;
  const directions = {
    ArrowLeft: [-1, 0],
    ArrowRight: [1, 0],
    ArrowUp: [0, -1],
    ArrowDown: [0, 1],
  };
  const direction = directions[event.key];
  if (!direction) return;
  event.preventDefault();
  const step = crop.value.side / 20;
  center.value = {
    x: center.value.x + direction[0] * step,
    y: center.value.y + direction[1] * step,
  };
  draw();
};
onMounted(async () => {
  dialog.value.open();
  await nextTick();
  const loaded = new Image();
  loaded.onload = () => {
    if (disposed) return;
    if (Math.min(loaded.naturalWidth, loaded.naturalHeight) < 192) {
      error.value = true;
      return;
    }
    image.value = loaded;
    reset();
  };
  loaded.onerror = () => {
    error.value = true;
  };
  loaded.src = url;
});
onBeforeUnmount(() => {
  disposed = true;
  URL.revokeObjectURL(url);
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="xl"
    overflow-y-auto
    :title="t('WHATSAPP_PROFILE.CROP_TITLE')"
    :description="t('WHATSAPP_PROFILE.CROP_HELP')"
    :confirm-button-label="t('WHATSAPP_PROFILE.SAVE_PHOTO')"
    :disable-confirm-button="!image || error"
    :is-loading="saving"
    :prevent-close="saving"
    @close="emit('close')"
    @confirm="emit('confirm', cropToJpeg(image, crop))"
  >
    <p v-if="error" role="alert" class="mb-0 text-sm text-n-ruby-11">
      {{ t('WHATSAPP_PROFILE.IMAGE_ERROR') }}
    </p>
    <canvas
      v-else
      ref="canvas"
      width="512"
      height="512"
      tabindex="0"
      :aria-label="t('WHATSAPP_PROFILE.CROP_HELP')"
      class="mx-auto aspect-square w-full max-w-[calc(100dvh-19rem)] touch-none rounded-lg bg-n-alpha-1 focus-visible:outline focus-visible:outline-n-blue-9"
      :class="dragging ? 'cursor-grabbing' : 'cursor-grab'"
      @pointerdown="startDrag"
      @pointermove="move"
      @pointerup="dragging = false"
      @pointercancel="dragging = false"
      @lostpointercapture="dragging = false"
      @keydown="panWithKeyboard"
    />
    <div class="flex items-center justify-between gap-3">
      <Button
        type="button"
        :label="t('WHATSAPP_PROFILE.RESET_CROP')"
        icon="i-lucide-rotate-ccw"
        slate
        ghost
        :disabled="!image || saving"
        @click="reset"
      />
      <div class="flex items-center gap-3">
        <Button
          type="button"
          :aria-label="t('WHATSAPP_PROFILE.ZOOM_OUT')"
          icon="i-lucide-minus"
          slate
          outline
          :disabled="zoom <= 1 || saving"
          @click="changeZoom(-0.1)"
        />
        <span class="min-w-12 text-center text-sm text-n-slate-11">{{
          t('WHATSAPP_PROFILE.ZOOM_PERCENT', {
            percent: Math.round(zoom * 100),
          })
        }}</span>
        <Button
          type="button"
          :aria-label="t('WHATSAPP_PROFILE.ZOOM_IN')"
          icon="i-lucide-plus"
          slate
          outline
          :disabled="zoom >= 4 || saving"
          @click="changeZoom(0.1)"
        />
      </div>
    </div>
  </Dialog>
</template>
