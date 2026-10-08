<script setup>
import { nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'next/button/Button.vue';
import Spinner from 'next/spinner/Spinner.vue';
import TeleportWithDirection from 'next/TeleportWithDirection.vue';
import Avatar from './Avatar.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  name: { type: String, default: '' },
  src: { type: String, default: '' },
  loading: { type: Boolean, default: false },
  error: { type: Boolean, default: false },
  photoStatus: { type: String, default: 'none' },
});
const emit = defineEmits(['close', 'retry']);
const { t } = useI18n();
const dialog = ref(null);
const failedImage = ref(false);
const syncDialog = async () => {
  await nextTick();
  if (props.show && !dialog.value.open) dialog.value.showModal();
  else if (!props.show && dialog.value.open) dialog.value.close();
};
watch(() => props.show, syncDialog);
watch(
  () => props.src,
  () => {
    failedImage.value = false;
  }
);
onMounted(syncDialog);
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      ref="dialog"
      :aria-label="t('WHATSAPP_PROFILE.VIEW_PHOTO')"
      class="fixed inset-0 m-0 h-screen max-h-none w-screen max-w-none border-0 bg-n-solid-1 p-0 text-n-slate-12 backdrop:bg-black/80"
      @cancel.prevent="emit('close')"
      @close="emit('close')"
    >
      <div v-if="show" class="flex h-full flex-col">
        <header
          class="flex shrink-0 items-center justify-between gap-4 border-b border-n-weak px-6 py-4"
        >
          <div class="flex min-w-0 items-center gap-3">
            <Avatar :src="src" :name="name" :size="36" />
            <span class="truncate text-base font-medium">{{ name }}</span>
          </div>
          <Button
            :aria-label="t('WHATSAPP_PROFILE.CLOSE')"
            icon="i-lucide-x"
            slate
            ghost
            @click="emit('close')"
          />
        </header>
        <div
          class="flex min-h-0 flex-1 items-center justify-center overflow-auto p-6"
        >
          <Spinner v-if="loading" />
          <div
            v-else-if="error || failedImage"
            class="flex flex-col items-center gap-4 text-center"
          >
            <p class="mb-0 text-sm text-n-slate-11">
              {{ t('WHATSAPP_PROFILE.PHOTO_ERROR') }}
            </p>
            <Button
              :label="t('WHATSAPP_PROFILE.RETRY')"
              icon="i-lucide-refresh-cw"
              slate
              outline
              @click="
                failedImage = false;
                emit('retry');
              "
            />
          </div>
          <img
            v-else-if="src"
            :src="src"
            :alt="t('WHATSAPP_PROFILE.PHOTO_ALT', { name })"
            class="max-h-full max-w-full object-contain"
            @error="failedImage = true"
          />
          <div v-else class="flex flex-col items-center gap-4 text-n-slate-11">
            <span class="i-lucide-user-round size-16" />
            <p class="mb-0 text-sm">
              {{
                t(
                  photoStatus === 'hidden'
                    ? 'WHATSAPP_PROFILE.PHOTO_HIDDEN'
                    : 'WHATSAPP_PROFILE.NO_PHOTO'
                )
              }}
            </p>
          </div>
        </div>
      </div>
    </dialog>
  </TeleportWithDirection>
</template>
