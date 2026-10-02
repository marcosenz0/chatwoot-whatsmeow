<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useIdle } from '@vueuse/core';
import { useEmitter } from 'dashboard/composables/emitter';
import { useI18n } from 'vue-i18n';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  createAppLock,
  verifyAppLock,
} from 'dashboard/helper/whatsmeowAppLock';
import Button from 'next/button/Button.vue';
import Input from 'next/input/Input.vue';
import Dialog from 'next/dialog/Dialog.vue';

const emit = defineEmits(['update:locked']);
const store = useStore();
const { t } = useI18n();
const key = computed(
  () => `whatsmeow-app-lock:${store.getters.getCurrentUserID}`
);
const config = ref(null);
const locked = ref(false);
const pin = ref('');
const confirmPin = ref('');
const error = ref('');
const busy = ref(false);
const settings = ref(null);
const lockDialog = ref(null);
const { idle } = useIdle(5 * 60 * 1000);
const canSet = computed(
  () => /^\d{6}$/.test(pin.value) && pin.value === confirmPin.value
);
async function lock() {
  if (!config.value) {
    settings.value.open();
    return;
  }
  pin.value = '';
  error.value = '';
  locked.value = true;
  emit('update:locked', true);
  await nextTick();
  lockDialog.value.showModal();
}
async function setLock() {
  busy.value = true;
  try {
    config.value = await createAppLock(pin.value);
    localStorage.setItem(key.value, JSON.stringify(config.value));
    settings.value.close();
    await lock();
  } catch {
    error.value = t('WHATSMEOW_UI.SAVE_ERROR');
  } finally {
    busy.value = false;
  }
}
async function unlock(remove = false) {
  busy.value = true;
  try {
    if (!(await verifyAppLock(pin.value, config.value))) {
      error.value = t('WHATSMEOW_UI.WRONG_PIN');
      return;
    }
    locked.value = false;
    emit('update:locked', false);
    lockDialog.value.close();
    pin.value = '';
    if (remove) {
      localStorage.removeItem(key.value);
      config.value = null;
    }
  } catch {
    error.value = t('WHATSMEOW_UI.SAVE_ERROR');
  } finally {
    busy.value = false;
  }
}
watch(
  key,
  async () => {
    config.value = JSON.parse(localStorage.getItem(key.value) || 'null');
    if (config.value) await lock();
  },
  { immediate: true, flush: 'post' }
);
watch(idle, value => {
  if (value && config.value && !locked.value) lock();
});
useEmitter(BUS_EVENTS.WHATSMEOW_APP_LOCK, lock);
</script>

<template>
  <Dialog
    ref="settings"
    :title="$t('WHATSMEOW_UI.APP_LOCK')"
    :description="$t('WHATSMEOW_UI.APP_LOCK_HELP')"
    :confirm-button-label="$t('WHATSMEOW_UI.ENABLE_LOCK')"
    :disable-confirm-button="!canSet"
    :is-loading="busy"
    @confirm="setLock"
    @close="
      pin = '';
      confirmPin = '';
      error = '';
    "
  >
    <Input
      v-model="pin"
      type="password"
      inputmode="numeric"
      maxlength="6"
      :label="$t('WHATSMEOW_UI.PIN')"
    />
    <Input
      v-model="confirmPin"
      type="password"
      inputmode="numeric"
      maxlength="6"
      :label="$t('WHATSMEOW_UI.CONFIRM_PIN')"
    />
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
  </Dialog>
  <Teleport to="body">
    <dialog
      ref="lockDialog"
      class="reset-base fixed inset-0 w-screen h-screen max-w-none max-h-none m-0 p-6 bg-n-background text-n-slate-12"
      @cancel.prevent
    >
      <form
        class="flex flex-col items-center justify-center min-h-full gap-4 mx-auto max-w-sm"
        @submit.prevent="unlock()"
      >
        <span class="i-lucide-lock-keyhole size-12 text-n-blue-11" />
        <h1 class="text-xl font-semibold">
          {{ $t('WHATSMEOW_UI.APP_LOCKED') }}
        </h1>
        <p class="text-sm text-center text-n-slate-11">
          {{ $t('WHATSMEOW_UI.UNLOCK_HELP') }}
        </p>
        <Input
          v-model="pin"
          type="password"
          inputmode="numeric"
          maxlength="6"
          :label="$t('WHATSMEOW_UI.PIN')"
          autofocus
          class="w-full"
        />
        <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
          {{ error }}
        </p>
        <Button
          :label="$t('WHATSMEOW_UI.UNLOCK')"
          :is-loading="busy"
          :disabled="!/^\d{6}$/.test(pin)"
          type="submit"
          class="w-full"
        />
        <Button
          :label="$t('WHATSMEOW_UI.DISABLE_LOCK')"
          ghost
          slate
          :disabled="busy"
          @click="unlock(true)"
        />
      </form>
    </dialog>
  </Teleport>
</template>
