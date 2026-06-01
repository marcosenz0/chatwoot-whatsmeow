<script setup>
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  shallowRef,
  watch,
} from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import SettingsAccordion from 'dashboard/components-next/Settings/SettingsAccordion.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: {
    type: Object,
    default: () => ({}),
  },
});

const STATUS_REQUEST_TIMEOUT = 15000;
const POLLING_INTERVAL = 3000;

const store = useStore();
const { t } = useI18n();

const settings = reactive({
  alwaysOnline: false,
  readMessages: false,
  rejectCalls: false,
  ignoreGroups: false,
  ignoreStatus: false,
  ignoreNewsletters: true,
  newsletter: false,
});

const connectionStatus = ref('disconnected');
const whatsmeowJid = ref('');
const qrCodeUrl = ref('');
const isFetchingStatus = ref(false);
const isPairing = ref(false);
const isDisconnecting = ref(false);
const pollInterval = ref(null);
const statusController = shallowRef(null);

const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);
const isConnected = computed(() => connectionStatus.value === 'connected');
const isConnecting = computed(
  () =>
    isPairing.value ||
    ['connecting', 'pairing'].includes(connectionStatus.value)
);

const statusLabel = computed(() => {
  if (isConnected.value) {
    return t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.STATUS.CONNECTED');
  }

  if (isConnecting.value) {
    return t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.STATUS.CONNECTING');
  }

  return t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.STATUS.DISCONNECTED');
});

const statusBadgeClass = computed(() => {
  if (isConnected.value) return 'bg-n-teal-3 text-n-teal-11';
  if (isConnecting.value) return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-ruby-3 text-n-ruby-11';
});

const statusDotClass = computed(() => {
  if (isConnected.value) return 'bg-n-teal-9';
  if (isConnecting.value) return 'bg-n-amber-9';
  return 'bg-n-ruby-9';
});

const statusDescription = computed(() => {
  if (isConnected.value) {
    return t(
      'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.STATUS.CONNECTED_DESCRIPTION'
    );
  }

  return t(
    'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.STATUS.DISCONNECTED_DESCRIPTION'
  );
});

const setDefaults = () => {
  settings.alwaysOnline = !!props.inbox.always_online;
  settings.readMessages = !!props.inbox.read_messages;
  settings.rejectCalls = !!props.inbox.reject_calls;
  settings.ignoreGroups = !!props.inbox.ignore_groups;
  settings.ignoreStatus = !!props.inbox.ignore_status;
  settings.ignoreNewsletters = props.inbox.ignore_newsletters !== false;
  settings.newsletter = !!props.inbox.newsletter;
  connectionStatus.value = props.inbox.status || 'disconnected';
};

const clearPolling = () => {
  if (pollInterval.value) {
    clearInterval(pollInterval.value);
    pollInterval.value = null;
  }
};

const cancelStatusRequest = () => {
  if (statusController.value) {
    statusController.value.abort();
    statusController.value = null;
  }
};

const applySessionPayload = payload => {
  const nextStatus = payload.status || 'disconnected';

  connectionStatus.value = nextStatus;
  whatsmeowJid.value = payload.jid || '';

  if (payload.qr_code) {
    qrCodeUrl.value = payload.qr_code;
  }

  if (nextStatus === 'connected') {
    isPairing.value = false;
    qrCodeUrl.value = '';
    clearPolling();
  }
};

const fetchWhatsmeowStatus = async ({ showLoader = false } = {}) => {
  if (!props.inbox.id) return;
  if (statusController.value) {
    if (!showLoader) return;
    cancelStatusRequest();
  }

  const controller = new AbortController();
  statusController.value = controller;
  isFetchingStatus.value = showLoader;

  try {
    const { data } = await InboxesAPI.getWhatsmeowStatus(props.inbox.id, {
      signal: controller.signal,
      timeout: STATUS_REQUEST_TIMEOUT,
    });
    applySessionPayload(data);
  } catch (error) {
    if (error.name !== 'CanceledError' && error.code !== 'ERR_CANCELED') {
      useAlert(t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.API.STATUS_ERROR'));
    }
  } finally {
    if (statusController.value === controller) {
      statusController.value = null;
      isFetchingStatus.value = false;
    }
  }
};

const startStatusPolling = () => {
  clearPolling();
  pollInterval.value = setInterval(fetchWhatsmeowStatus, POLLING_INTERVAL);
};

const generateQRCode = async () => {
  if (!props.inbox.id) return;

  isPairing.value = true;
  qrCodeUrl.value = '';

  try {
    const { data } = await InboxesAPI.createWhatsmeowSession(
      props.inbox.id,
      {},
      { timeout: STATUS_REQUEST_TIMEOUT }
    );
    applySessionPayload(data);

    if (!isConnected.value) {
      startStatusPolling();
    } else {
      useAlert(t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.API.CONNECTED'));
    }
  } catch (error) {
    isPairing.value = false;
    clearPolling();
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.API.QR_ERROR'));
  }
};

const cancelPairing = () => {
  isPairing.value = false;
  clearPolling();
};

const disconnectSession = async () => {
  if (!props.inbox.id) return;

  isDisconnecting.value = true;
  clearPolling();

  try {
    const { data } = await InboxesAPI.deleteWhatsmeowSession(props.inbox.id, {
      timeout: STATUS_REQUEST_TIMEOUT,
    });
    applySessionPayload(data);
    qrCodeUrl.value = '';
    isPairing.value = false;
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.API.DISCONNECTED'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.API.DISCONNECT_ERROR'));
  } finally {
    isDisconnecting.value = false;
  }
};

const updateWhatsmeowSettings = async () => {
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: {
        always_online: settings.alwaysOnline,
        read_messages: settings.readMessages,
        reject_calls: settings.rejectCalls,
        ignore_groups: settings.ignoreGroups,
        ignore_status: settings.ignoreStatus,
        ignore_newsletters: settings.ignoreNewsletters,
        newsletter: settings.newsletter,
      },
    });
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};

watch(() => props.inbox.id, setDefaults, { immediate: true });

onMounted(fetchWhatsmeowStatus);
onBeforeUnmount(() => {
  clearPolling();
  cancelStatusRequest();
});
</script>

<template>
  <div class="space-y-6">
    <SettingsToggleSection
      hide-toggle
      :header="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.STATUS.TITLE')"
      :description="statusDescription"
    >
      <template #hiddenToggle>
        <span
          class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium"
          :class="statusBadgeClass"
        >
          <span class="size-1.5 rounded-full" :class="statusDotClass" />
          {{ statusLabel }}
        </span>
      </template>

      <template #editor>
        <div class="flex flex-col gap-4">
          <div
            v-if="isConnected && whatsmeowJid"
            class="text-body-main text-n-slate-11"
          >
            {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.STATUS.JID') }}
            <code
              class="rounded bg-n-slate-3 px-1.5 py-0.5 text-xs text-n-slate-12"
            >
              {{ whatsmeowJid }}
            </code>
          </div>

          <div
            v-if="isPairing && !isConnected"
            class="flex flex-col items-center gap-4 rounded-xl bg-n-slate-2 p-5 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div class="flex flex-col items-center gap-1 text-center">
              <span class="text-heading-3 text-n-slate-12">
                {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.QR.TITLE') }}
              </span>
              <span class="text-body-main text-n-slate-11">
                {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.QR.DESCRIPTION') }}
              </span>
            </div>

            <div
              class="flex size-64 items-center justify-center rounded-xl bg-white p-4 outline outline-1 -outline-offset-1 outline-n-weak"
            >
              <img
                v-if="qrCodeUrl"
                :src="qrCodeUrl"
                :alt="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.QR.IMAGE_ALT')"
                class="size-56"
              />
              <span
                v-else
                class="i-lucide-loader-circle size-8 animate-spin text-n-slate-11"
              />
            </div>

            <span class="text-label-small text-n-slate-11">
              {{ $t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.QR.WAITING') }}
            </span>
          </div>

          <div class="flex flex-wrap justify-end gap-2">
            <NextButton
              outline
              slate
              size="sm"
              icon="i-lucide-refresh-cw"
              :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.STATUS.REFRESH')"
              :is-loading="isFetchingStatus"
              :disabled="isFetchingStatus"
              @click="fetchWhatsmeowStatus({ showLoader: true })"
            />
            <NextButton
              v-if="isConnected"
              outline
              ruby
              size="sm"
              icon="i-lucide-unplug"
              :label="
                $t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.STATUS.DISCONNECT')
              "
              :is-loading="isDisconnecting"
              :disabled="isDisconnecting"
              @click="disconnectSession"
            />
            <NextButton
              v-if="!isConnected"
              size="sm"
              icon="i-lucide-plug"
              :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.STATUS.CONNECT')"
              :is-loading="isPairing && !qrCodeUrl"
              :disabled="isPairing"
              @click="generateQRCode"
            />
            <NextButton
              v-if="isPairing && !isConnected"
              outline
              ruby
              size="sm"
              :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.QR.CANCEL')"
              @click="cancelPairing"
            />
          </div>
        </div>
      </template>
    </SettingsToggleSection>

    <SettingsAccordion
      :title="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.TITLE')"
    >
      <div class="space-y-3">
        <SettingsToggleSection
          v-model="settings.alwaysOnline"
          :header="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.ALWAYS_ONLINE.LABEL'
            )
          "
          :description="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.ALWAYS_ONLINE.DESCRIPTION'
            )
          "
        />
        <SettingsToggleSection
          v-model="settings.readMessages"
          :header="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.READ_MESSAGES.LABEL'
            )
          "
          :description="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.READ_MESSAGES.DESCRIPTION'
            )
          "
        />
        <SettingsToggleSection
          v-model="settings.rejectCalls"
          :header="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.REJECT_CALLS.LABEL'
            )
          "
          :description="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.REJECT_CALLS.DESCRIPTION'
            )
          "
        />
        <SettingsToggleSection
          v-model="settings.ignoreGroups"
          :header="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.IGNORE_GROUPS.LABEL'
            )
          "
          :description="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.IGNORE_GROUPS.DESCRIPTION'
            )
          "
        />
        <SettingsToggleSection
          v-model="settings.ignoreStatus"
          :header="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.IGNORE_STATUS.LABEL'
            )
          "
          :description="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.IGNORE_STATUS.DESCRIPTION'
            )
          "
        />
        <SettingsToggleSection
          v-model="settings.ignoreNewsletters"
          :header="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.IGNORE_NEWSLETTERS.LABEL'
            )
          "
          :description="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.IGNORE_NEWSLETTERS.DESCRIPTION'
            )
          "
        />
        <SettingsToggleSection
          v-model="settings.newsletter"
          :header="
            $t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.NEWSLETTER.LABEL')
          "
          :description="
            $t(
              'INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.NEWSLETTER.DESCRIPTION'
            )
          "
        />
      </div>

      <div class="mt-4 flex justify-end">
        <NextButton
          :label="$t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.SETTINGS.SAVE')"
          :is-loading="uiFlags.isUpdating"
          @click="updateWhatsmeowSettings"
        />
      </div>
    </SettingsAccordion>
  </div>
</template>
