<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import ChatsAPI from 'dashboard/api/whatsmeowConversations';
import Button from 'next/button/Button.vue';
import DropdownMenu from 'next/dropdown-menu/DropdownMenu.vue';
import Dialog from 'next/dialog/Dialog.vue';
import CreateGroupDialog from './CreateGroupDialog.vue';

const store = useStore();
const { t } = useI18n();
const visible = ref(false);
const newGroup = ref(false);
const dialog = ref(null);
const mode = ref('');
const busy = ref(false);
const error = ref('');
const inboxId = ref(null);
const inboxes = computed(() =>
  store.getters['inboxes/getInboxes'].filter(
    i => i.channel_type === 'Channel::Whatsmeow'
  )
);
const administrator = computed(() =>
  store.getters.getCurrentUser?.accounts?.some(
    a =>
      Number(a.id) === Number(store.getters.getCurrentAccountId) &&
      a.role === 'administrator'
  )
);
const items = computed(() =>
  [
    'new_group',
    'starred_messages',
    'select_conversations',
    'read_all',
    'app_lock',
    ...(administrator.value ? ['disconnect'] : []),
  ].map(action => ({
    label: t(`WHATSMEOW_UI.${action.toUpperCase()}`),
    action,
    value: action,
    icon: {
      new_group: 'i-lucide-users',
      starred_messages: 'i-lucide-star',
      select_conversations: 'i-lucide-square-check',
      read_all: 'i-lucide-check-check',
      app_lock: 'i-lucide-lock-keyhole',
      disconnect: 'i-lucide-log-out',
    }[action],
  }))
);
function select({ action }) {
  visible.value = false;
  if (action === 'new_group') newGroup.value = true;
  if (action === 'starred_messages')
    emitter.emit(BUS_EVENTS.WHATSMEOW_STARRED_MESSAGES, {});
  if (action === 'select_conversations')
    emitter.emit(BUS_EVENTS.WHATSMEOW_SELECT_CONVERSATIONS);
  if (action === 'app_lock') emitter.emit(BUS_EVENTS.WHATSMEOW_APP_LOCK);
  if (['read_all', 'disconnect'].includes(action)) {
    mode.value = action;
    inboxId.value = action === 'disconnect' ? inboxes.value[0]?.id : null;
    error.value = '';
    dialog.value.open();
  }
}
async function confirm() {
  busy.value = true;
  try {
    if (mode.value === 'disconnect')
      await InboxesAPI.deleteWhatsmeowSession(inboxId.value);
    else {
      await ChatsAPI.readAll(inboxId.value);
      emitter.emit('fetch_conversation_stats');
      await store.dispatch('conversationUnreadCounts/get');
      emitter.emit('fetch_conversations');
    }
    dialog.value.close();
    useAlert(t('WHATSMEOW_UI.SAVED'));
  } catch (e) {
    error.value = e.response?.data?.message || t('WHATSMEOW_UI.SAVE_ERROR');
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div
    v-if="inboxes.length"
    v-on-clickaway="() => (visible = false)"
    class="relative"
  >
    <Button
      icon="i-lucide-more-vertical"
      ghost
      slate
      xs
      :aria-label="$t('WHATSMEOW_UI.MORE_OPTIONS')"
      @click="visible = !visible"
    />
    <DropdownMenu
      v-if="visible"
      :menu-items="items"
      class="right-0 top-full mt-1"
      @action="select"
    />
    <CreateGroupDialog v-if="newGroup" @close="newGroup = false" />
    <Dialog
      ref="dialog"
      :title="
        $t(
          mode === 'disconnect'
            ? 'WHATSMEOW_UI.DISCONNECT'
            : 'WHATSMEOW_UI.READ_ALL'
        )
      "
      :description="
        $t(
          mode === 'disconnect'
            ? 'WHATSMEOW_UI.DISCONNECT_CONFIRM'
            : 'WHATSMEOW_UI.READ_ALL_CONFIRM'
        )
      "
      :is-loading="busy"
      :prevent-close="busy"
      @confirm="confirm"
    >
      <select
        v-model="inboxId"
        class="reset-base p-2 rounded-lg border border-n-weak bg-n-surface-1"
      >
        <option v-if="mode === 'read_all'" :value="null">
          {{ $t('WHATSMEOW_UI.ALL_INBOXES') }}
        </option>
        <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
          {{ inbox.name }}
        </option>
      </select>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
    </Dialog>
  </div>
</template>
