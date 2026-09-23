<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';

const props = defineProps({ inbox: { type: Object, required: true } });
const store = useStore();
const { t } = useI18n();
const state = ref({});
const automatic = ref(true);
const days = ref(90);
const from = ref('');
const busy = ref(false);
let interval;
let fetching = false;
const today = new Date().toLocaleDateString('en-CA');
const active = computed(() =>
  ['syncing', 'waiting'].includes(state.value.phase)
);
const phaseLabel = computed(
  () =>
    ({
      idle: t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.PHASE.IDLE'),
      syncing: t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.PHASE.SYNCING'),
      waiting: t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.PHASE.WAITING'),
      partial: t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.PHASE.PARTIAL'),
      paused: t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.PHASE.PAUSED'),
      error: t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.PHASE.ERROR'),
    })[state.value.phase || 'idle']
);
const lastUpdate = computed(() =>
  state.value.updated_at
    ? new Date(state.value.updated_at * 1000).toLocaleString()
    : t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.NOT_YET')
);

const refresh = async () => {
  if (fetching || document.hidden) return;
  const id = props.inbox.id;
  fetching = true;
  try {
    const { data } = await InboxesAPI.getWhatsmeowHistoryState(id);
    if (props.inbox.id !== id) return;
    state.value = data;
    store.commit('inboxes/EDIT_INBOXES', {
      ...props.inbox,
      history_sync_state: data,
    });
  } catch {
    // Keep the last known state while the service is temporarily unavailable.
  } finally {
    fetching = false;
  }
};

const save = async () => {
  await store.dispatch('inboxes/updateInbox', {
    id: props.inbox.id,
    formData: false,
    channel: {
      history_sync_days: Number(days.value),
      history_sync_auto: automatic.value,
    },
  });
};

const run = async action => {
  busy.value = true;
  try {
    if (action === 'save') {
      await save();
    } else {
      const timestamp = Math.floor(
        new Date(`${from.value}T00:00:00`).getTime() / 1000
      );
      if (action === 'start') await save();
      await InboxesAPI.syncWhatsmeowHistory(props.inbox.id, {
        from: timestamp,
        pause: action === 'pause',
      });
    }
    await refresh();
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.SAVED'));
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.ERROR')
    );
  } finally {
    busy.value = false;
  }
};

watch(
  () => props.inbox.id,
  () => {
    days.value = props.inbox.history_sync_days || 90;
    automatic.value = props.inbox.history_sync_auto !== false;
    state.value = props.inbox.history_sync_state || {};
    const date = new Date();
    date.setDate(date.getDate() - days.value);
    from.value = date.toLocaleDateString('en-CA');
  },
  { immediate: true }
);

onMounted(() => {
  refresh();
  interval = setInterval(refresh, 5000);
});
onBeforeUnmount(() => clearInterval(interval));
</script>

<template>
  <section class="space-y-4 rounded-xl border border-n-weak p-4">
    <h3 class="text-heading-3 text-n-slate-12">
      {{ t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.TITLE') }}
    </h3>
    <p class="text-sm text-n-slate-11">
      {{ t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.DESCRIPTION') }}
    </p>
    <SettingsToggleSection
      v-model="automatic"
      :header="t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.AUTO')"
      :description="
        t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.AUTO_DESCRIPTION')
      "
    />
    <div class="grid gap-4 sm:grid-cols-2">
      <label class="text-sm text-n-slate-12">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.DAYS') }}
        <input
          v-model="days"
          type="number"
          min="1"
          max="3650"
          class="mt-2 w-full"
        />
      </label>
      <label class="text-sm text-n-slate-12">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.FROM') }}
        <input v-model="from" type="date" :max="today" class="mt-2 w-full" />
      </label>
    </div>
    <div
      role="status"
      aria-live="polite"
      class="space-y-2 rounded-lg bg-n-slate-2 p-3 text-sm text-n-slate-11"
    >
      <div class="flex items-center gap-2 font-medium text-n-slate-12">
        <span
          v-if="active"
          class="i-lucide-loader-circle size-4 animate-spin"
        />
        {{ phaseLabel }}
      </div>
      <p>
        {{
          t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.COUNTS', {
            stored: state.stored || 0,
            conversations: state.conversations || 0,
            received: state.received || 0,
            pending: state.pending || 0,
          })
        }}
      </p>
      <p v-if="state.imported">
        {{
          t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.PROCESSED', {
            imported: state.imported,
          })
        }}
      </p>
      <p>
        {{
          t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.UPDATED', {
            time: lastUpdate,
          })
        }}
      </p>
      <p v-if="state.unavailable">
        {{
          t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.UNAVAILABLE', {
            count: state.unavailable,
          })
        }}
      </p>
      <p v-if="state.failed">
        {{
          t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.FAILED', {
            count: state.failed,
          })
        }}
      </p>
    </div>
    <p class="text-xs text-n-slate-11">
      {{ t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.LIMITS') }}
    </p>
    <div class="flex flex-wrap justify-end gap-2">
      <NextButton
        :label="t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.SAVE')"
        outline
        :disabled="busy"
        @click="run('save')"
      />
      <NextButton
        v-if="active"
        :label="t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.PAUSE')"
        outline
        :disabled="busy"
        @click="run('pause')"
      />
      <NextButton
        :label="t('INBOX_MGMT.SETTINGS_POPUP.WHATSMEOW.HISTORY.START')"
        icon="i-lucide-refresh-cw"
        :is-loading="busy"
        :disabled="busy || active || !from"
        @click="run('start')"
      />
    </div>
  </section>
</template>
