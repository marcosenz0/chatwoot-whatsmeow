<script setup>
import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import InboxesAPI from 'dashboard/api/inboxes';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({ inboxId: { type: Number, required: true } });
const emit = defineEmits(['connected', 'disconnected']);
const { t } = useI18n();
const session = ref({ status: 'disconnected' });
const password = ref('');
const busy = ref(false);
const error = ref('');
let timer;
let disposed = false;
const qrCode = computed(() => {
  if (session.value.expires_at * 1000 <= Date.now()) return '';
  return session.value.qr_code || '';
});
const apply = data => {
  const previous = session.value.status;
  session.value = data;
  error.value = data.error ? t(`TELEGRAM_PERSONAL.ERRORS.${data.error}`) : '';
  if (data.status === 'connected' && previous !== 'connected')
    emit('connected');
  if (data.status === 'disconnected' && previous === 'connected')
    emit('disconnected');
};
const poll = async () => {
  try {
    const { data } = await InboxesAPI.getTelegramPersonalStatus(props.inboxId);
    if (!disposed) apply(data);
  } catch {
    if (!disposed) {
      error.value = t('TELEGRAM_PERSONAL.ERRORS.service_unavailable');
      session.value = { status: 'error' };
    }
  } finally {
    if (!disposed) timer = setTimeout(poll, 3000);
  }
};
const run = async action => {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await action();
    if (!disposed) apply(data);
  } catch (e) {
    error.value = t(
      `TELEGRAM_PERSONAL.ERRORS.${e.response?.data?.error || 'service_unavailable'}`
    );
  } finally {
    busy.value = false;
  }
};
const connect = () =>
  run(() => InboxesAPI.connectTelegramPersonal(props.inboxId));
const disconnect = () =>
  run(() => InboxesAPI.disconnectTelegramPersonal(props.inboxId));
const submitPassword = () => {
  const { value } = password;
  password.value = '';
  return run(() =>
    InboxesAPI.submitTelegramPersonalPassword(props.inboxId, value)
  );
};
onMounted(poll);
onBeforeUnmount(() => {
  disposed = true;
  clearTimeout(timer);
  password.value = '';
});
</script>

<template>
  <section
    class="flex max-w-lg flex-col gap-4 rounded-xl border border-n-weak bg-n-surface-1 p-6"
    aria-live="polite"
  >
    <h3 class="text-lg font-medium text-n-slate-12">
      {{ t('TELEGRAM_PERSONAL.TITLE') }}
    </h3>
    <p class="text-n-slate-11">
      {{ t(`TELEGRAM_PERSONAL.STATUS.${session.status}`) }}
    </p>
    <p v-if="error" class="text-n-ruby-11" role="alert">{{ error }}</p>
    <template v-if="session.status === 'qr'">
      <p class="text-n-slate-11">{{ t('TELEGRAM_PERSONAL.SCAN') }}</p>
      <div
        class="flex size-64 items-center justify-center rounded-lg bg-white p-4"
      >
        <img
          v-if="qrCode"
          :src="qrCode"
          :alt="t('TELEGRAM_PERSONAL.QR_ALT')"
          class="size-56"
        />
        <span
          v-else
          class="i-lucide-loader-circle size-8 animate-spin text-n-slate-11"
        />
      </div>
      <p class="text-sm text-n-slate-11">
        {{ t('TELEGRAM_PERSONAL.QR_REFRESH') }}
      </p>
    </template>
    <form
      v-if="session.status === 'password'"
      class="flex flex-col gap-3"
      @submit.prevent="submitPassword"
    >
      <label>
        {{ t('TELEGRAM_PERSONAL.PASSWORD') }}
        <input
          v-model="password"
          type="password"
          autocomplete="off"
          required
          maxlength="256"
        />
      </label>
      <NextButton
        type="submit"
        :label="t('TELEGRAM_PERSONAL.CONFIRM')"
        :is-loading="busy"
      />
    </form>
    <template v-if="session.status === 'connected'">
      <p class="text-n-teal-11">
        {{
          session.username ? `@${session.username}` : session.telegram_user_id
        }}
      </p>
      <NextButton
        outline
        ruby
        :label="t('TELEGRAM_PERSONAL.DISCONNECT')"
        :is-loading="busy"
        @click="disconnect"
      />
    </template>
    <NextButton
      v-if="['disconnected', 'error'].includes(session.status)"
      :label="t('TELEGRAM_PERSONAL.CONNECT')"
      :is-loading="busy"
      @click="connect"
    />
    <p class="text-sm text-n-slate-11">{{ t('TELEGRAM_PERSONAL.APP_ONCE') }}</p>
    <a
      href="https://my.telegram.org/apps"
      target="_blank"
      rel="noopener noreferrer"
      class="text-n-blue-11"
    >
      {{ t('TELEGRAM_PERSONAL.DEVELOPER_LINK') }}
    </a>
  </section>
</template>
