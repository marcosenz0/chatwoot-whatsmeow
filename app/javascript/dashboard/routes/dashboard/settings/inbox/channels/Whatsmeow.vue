<script setup>
import { computed, onBeforeUnmount, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();

const formState = reactive({
  channelName: '',
});

const validationRules = {
  channelName: { required },
};

const v$ = useVuelidate(validationRules, formState);
const inboxId = ref(null);
const qrCodeUrl = ref('');
const isPairing = ref(false);
const isPaired = ref(false);
const isStartingSession = ref(false);
const pollInterval = ref(null);

const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);

const clearPolling = () => {
  if (pollInterval.value) {
    clearInterval(pollInterval.value);
    pollInterval.value = null;
  }
};

const redirectToAgents = () => {
  router.replace({
    name: 'settings_inboxes_add_agents',
    params: {
      page: 'new',
      inbox_id: inboxId.value,
    },
  });
};

const handlePairingSuccess = () => {
  isPaired.value = true;
  isPairing.value = false;
  qrCodeUrl.value = '';
  clearPolling();
  useAlert(t('INBOX_MGMT.ADD.WHATSMEOW.API.CONNECTED'));
  setTimeout(redirectToAgents, 1200);
};

const applySessionPayload = payload => {
  if (payload.qr_code) {
    qrCodeUrl.value = payload.qr_code;
  }

  if (payload.status === 'connected') {
    handlePairingSuccess();
  }
};

const pollStatus = async () => {
  if (!inboxId.value) return;

  try {
    const { data } = await InboxesAPI.getWhatsmeowStatus(inboxId.value);
    applySessionPayload(data);
  } catch (error) {
    clearPolling();
    useAlert(t('INBOX_MGMT.ADD.WHATSMEOW.API.STATUS_ERROR'));
  }
};

const startStatusPolling = () => {
  clearPolling();
  pollInterval.value = setInterval(pollStatus, 3000);
};

const startWhatsmeowSession = async id => {
  isStartingSession.value = true;

  try {
    const { data } = await InboxesAPI.createWhatsmeowSession(id, {
      force_new: true,
    });
    applySessionPayload(data);

    if (!isPaired.value) {
      startStatusPolling();
    }
  } catch (error) {
    isPairing.value = false;
    useAlert(t('INBOX_MGMT.ADD.WHATSMEOW.API.SERVICE_ERROR'));
  } finally {
    isStartingSession.value = false;
  }
};

const createChannel = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    const whatsmeowChannel = await store.dispatch('inboxes/createChannel', {
      name: formState.channelName.trim(),
      channel: {
        type: 'whatsmeow',
      },
    });

    inboxId.value = whatsmeowChannel.id;
    isPairing.value = true;
    await startWhatsmeowSession(whatsmeowChannel.id);
  } catch (error) {
    useAlert(error.message || t('INBOX_MGMT.ADD.WHATSMEOW.API.ERROR_MESSAGE'));
  }
};

onBeforeUnmount(clearPolling);
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      :header-title="$t('INBOX_MGMT.ADD.WHATSMEOW.TITLE')"
      :header-content="$t('INBOX_MGMT.ADD.WHATSMEOW.DESC')"
    />

    <form
      v-if="!isPairing && !isPaired"
      class="flex flex-wrap flex-col mx-0"
      @submit.prevent="createChannel"
    >
      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.channelName.$error }">
          {{ $t('INBOX_MGMT.ADD.WHATSMEOW.CHANNEL_NAME.LABEL') }}
          <input
            v-model="formState.channelName"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.WHATSMEOW.CHANNEL_NAME.PLACEHOLDER')
            "
            @blur="v$.channelName.$touch"
          />
          <span v-if="v$.channelName.$error" class="message">
            {{ $t('INBOX_MGMT.ADD.WHATSMEOW.CHANNEL_NAME.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-full mt-6">
        <NextButton
          type="submit"
          solid
          blue
          :is-loading="uiFlags.isCreating"
          :label="$t('INBOX_MGMT.ADD.WHATSMEOW.SUBMIT_BUTTON')"
        />
      </div>
    </form>

    <div
      v-else-if="isPairing && !isPaired"
      class="mt-6 flex max-w-md flex-col items-center gap-4 rounded-xl bg-n-slate-2 p-6 text-center outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <div class="flex flex-col gap-1">
        <span class="text-heading-2 text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSMEOW.PAIRING.TITLE') }}
        </span>
        <span class="text-body-main text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.WHATSMEOW.PAIRING.DESCRIPTION') }}
        </span>
      </div>

      <div
        class="flex size-64 items-center justify-center rounded-xl bg-white p-4 outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <img
          v-if="qrCodeUrl"
          :src="qrCodeUrl"
          :alt="$t('INBOX_MGMT.ADD.WHATSMEOW.PAIRING.IMAGE_ALT')"
          class="size-56"
        />
        <span
          v-else
          class="i-lucide-loader-circle size-8 animate-spin text-n-slate-11"
        />
      </div>

      <span class="text-label-small text-n-slate-11">
        {{ $t('INBOX_MGMT.ADD.WHATSMEOW.PAIRING.WAITING') }}
      </span>

      <NextButton
        outline
        slate
        size="sm"
        icon="i-lucide-refresh-cw"
        :is-loading="isStartingSession"
        :label="$t('INBOX_MGMT.ADD.WHATSMEOW.PAIRING.REFRESH')"
        @click="startWhatsmeowSession(inboxId)"
      />
    </div>

    <div
      v-else-if="isPaired"
      class="mt-6 flex max-w-md flex-col items-center gap-3 rounded-xl bg-n-teal-2 p-6 text-center outline outline-1 -outline-offset-1 outline-n-teal-5"
    >
      <span class="i-lucide-circle-check-big size-10 text-n-teal-10" />
      <span class="text-heading-2 text-n-slate-12">
        {{ $t('INBOX_MGMT.ADD.WHATSMEOW.SUCCESS.TITLE') }}
      </span>
      <span class="text-body-main text-n-slate-11">
        {{ $t('INBOX_MGMT.ADD.WHATSMEOW.SUCCESS.DESCRIPTION') }}
      </span>
    </div>
  </div>
</template>
