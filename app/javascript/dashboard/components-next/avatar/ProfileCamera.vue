<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'next/dialog/Dialog.vue';
import Spinner from 'next/spinner/Spinner.vue';

const emit = defineEmits(['capture', 'close']);
const { t } = useI18n();
const dialog = ref(null);
const video = ref(null);
const loading = ref(true);
const ready = ref(false);
const error = ref(false);
let stream;
let disposed = false;
const stop = () => {
  stream?.getTracks().forEach(track => track.stop());
};
const capture = () => {
  const canvas = document.createElement('canvas');
  canvas.width = video.value.videoWidth;
  canvas.height = video.value.videoHeight;
  canvas.getContext('2d').drawImage(video.value, 0, 0);
  canvas.toBlob(
    blob => {
      if (blob && !disposed) {
        stop();
        emit('capture', blob);
      }
    },
    'image/jpeg',
    0.95
  );
};
onMounted(async () => {
  dialog.value.open();
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: {
        facingMode: 'user',
        width: { ideal: 1280 },
        height: { ideal: 720 },
      },
      audio: false,
    });
    if (disposed) {
      stop();
      return;
    }
    video.value.srcObject = stream;
    await video.value.play();
  } catch {
    if (!disposed) error.value = true;
  } finally {
    loading.value = false;
  }
});
onBeforeUnmount(() => {
  disposed = true;
  stop();
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="xl"
    :title="t('WHATSAPP_PROFILE.TAKE_PHOTO')"
    :confirm-button-label="t('WHATSAPP_PROFILE.CAPTURE')"
    :disable-confirm-button="!ready || error || loading"
    @close="emit('close')"
    @confirm="capture"
  >
    <Spinner v-if="loading" />
    <p v-if="error" role="alert" class="mb-0 text-sm text-n-ruby-11">
      {{ t('WHATSAPP_PROFILE.CAMERA_ERROR') }}
    </p>
    <video
      ref="video"
      autoplay
      muted
      playsinline
      :aria-label="t('WHATSAPP_PROFILE.CAMERA_PREVIEW')"
      class="aspect-video w-full rounded-lg bg-n-alpha-1 object-contain"
      :class="{ hidden: error }"
      @loadeddata="ready = true"
    />
  </Dialog>
</template>
