<script setup>
import { ref, computed, onMounted, onUnmounted, useAttrs } from 'vue';
import { useMapGetter } from 'dashboard/composables/store.js';
import { getUnixTime } from 'date-fns';
import { findSnoozeTime } from 'dashboard/helper/snoozeHelpers';
import { emitter } from 'shared/helpers/mitt';
import { useBulkActions } from 'dashboard/composables/chatlist/useBulkActions.js';
import wootConstants from 'dashboard/constants/globals';
import {
  CMD_BULK_ACTION_SNOOZE_CONVERSATION,
  CMD_BULK_ACTION_REOPEN_CONVERSATION,
  CMD_BULK_ACTION_RESOLVE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import BulkAgentActions from './BulkAgentActions.vue';
import BulkUpdateActions from './BulkUpdateActions.vue';
import BulkLabelActions from './BulkLabelActions.vue';
import BulkTeamActions from './BulkTeamActions.vue';
import CustomSnoozeModal from 'dashboard/components/CustomSnoozeModal.vue';

const props = defineProps({
  conversations: {
    type: Array,
    default: () => [],
  },
  allConversationsSelected: {
    type: Boolean,
    default: false,
  },
  selectedInboxes: {
    type: Array,
    default: () => [],
  },
  showOpenAction: {
    type: Boolean,
    default: false,
  },
  showResolvedAction: {
    type: Boolean,
    default: false,
  },
  showSnoozedAction: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['selectAllConversations', 'deleteConversations']);

defineOptions({
  inheritAttrs: false,
});

const attrs = useAttrs();

const {
  selectedConversations,
  onAssignAgent,
  onAssignLabels,
  onRemoveLabels,
  onAssignTeamsForBulk: onAssignTeam,
  onUpdateConversations,
  onDeleteConversations,
} = useBulkActions();

const getConversationById = useMapGetter('getConversationById');

const appliedLabelsForSelection = computed(() => {
  const applied = new Set();
  selectedConversations.value.forEach(id => {
    const conversation = getConversationById.value(id);
    (conversation?.labels || []).forEach(label => applied.add(label));
  });
  return Array.from(applied);
});

const showCustomTimeSnoozeModal = ref(false);
const deleteConversationsDialogRef = ref(null);
const pendingDeleteConversationIds = ref([]);
const isDeletingConversations = ref(false);

function onCmdSnoozeConversation(snoozeType) {
  if (snoozeType === wootConstants.SNOOZE_OPTIONS.UNTIL_CUSTOM_TIME) {
    showCustomTimeSnoozeModal.value = true;
  } else if (typeof snoozeType === 'number') {
    onUpdateConversations('snoozed', snoozeType);
  } else {
    onUpdateConversations('snoozed', findSnoozeTime(snoozeType) || null);
  }
}

function onCmdReopenConversation() {
  onUpdateConversations('open', null);
}

function onCmdResolveConversation() {
  onUpdateConversations('resolved', null);
}

function customSnoozeTime(customSnoozedTime) {
  showCustomTimeSnoozeModal.value = false;
  if (customSnoozedTime) {
    onUpdateConversations('snoozed', getUnixTime(customSnoozedTime));
  }
}

function hideCustomSnoozeModal() {
  showCustomTimeSnoozeModal.value = false;
}

function openDeleteConversationsDialog() {
  pendingDeleteConversationIds.value = [...selectedConversations.value];
  deleteConversationsDialogRef.value?.open();
}

function clearPendingDeleteConversations() {
  pendingDeleteConversationIds.value = [];
}

async function confirmDeleteConversations() {
  isDeletingConversations.value = true;
  const ids = [...pendingDeleteConversationIds.value];
  const deleted = await onDeleteConversations(ids);
  isDeletingConversations.value = false;

  if (deleted) {
    deleteConversationsDialogRef.value?.close();
    emit('deleteConversations', ids);
  }
}

// Computed property with getter/setter to enable v-model usage
const allSelected = computed({
  get: () => props.allConversationsSelected,
  set: value => {
    emit('selectAllConversations', value);
  },
});

onMounted(() => {
  emitter.on(CMD_BULK_ACTION_SNOOZE_CONVERSATION, onCmdSnoozeConversation);
  emitter.on(CMD_BULK_ACTION_REOPEN_CONVERSATION, onCmdReopenConversation);
  emitter.on(CMD_BULK_ACTION_RESOLVE_CONVERSATION, onCmdResolveConversation);
});

onUnmounted(() => {
  emitter.off(CMD_BULK_ACTION_SNOOZE_CONVERSATION, onCmdSnoozeConversation);
  emitter.off(CMD_BULK_ACTION_REOPEN_CONVERSATION, onCmdReopenConversation);
  emitter.off(CMD_BULK_ACTION_RESOLVE_CONVERSATION, onCmdResolveConversation);
});
</script>

<template>
  <Transition
    enter-active-class="transition-all duration-200 ease-out origin-bottom"
    enter-from-class="opacity-0 scale-95 translate-y-2"
    enter-to-class="opacity-100 scale-100 translate-y-0"
    leave-active-class="transition-all duration-150 ease-in origin-bottom"
    leave-from-class="opacity-100 scale-100 translate-y-0"
    leave-to-class="opacity-0 scale-95 translate-y-2"
  >
    <div
      v-if="conversations.length > 0"
      v-bind="attrs"
      class="fixed bottom-4 left-0 right-0 z-30 origin-bottom px-3 lg:left-[calc(14rem+340px+1rem)] lg:right-[22rem] 2xl:left-[calc(14rem+412px+1rem)]"
    >
      <div
        v-if="allConversationsSelected"
        class="bg-n-amber-2 outline -outline-offset-1 outline-1 outline-n-amber-5 rounded-lg text-sm mb-2 py-1.5 px-2 text-n-amber-text"
      >
        {{ $t('BULK_ACTION.ALL_CONVERSATIONS_SELECTED_ALERT') }}
      </div>
      <div
        class="mx-auto flex min-h-14 w-full max-w-[42rem] flex-wrap items-center justify-between gap-3 bg-n-button-color px-3 py-2.5 outline outline-1 -outline-offset-1 rounded-[10px] outline-n-weak shadow-[0_0_12px_0_rgba(27,40,59,0.08)] sm:flex-nowrap"
      >
        <div
          class="ltr:ml-0.5 rtl:mr-0.5 flex min-w-0 flex-1 items-center gap-1"
        >
          <label class="cursor-pointer flex min-w-0 items-center gap-1.5">
            <Checkbox
              v-model="allSelected"
              :indeterminate="!allConversationsSelected"
            />
            <span class="cursor-pointer truncate text-sm">
              {{
                $t('BULK_ACTION.CONVERSATIONS_SELECTED', {
                  conversationCount: conversations.length,
                })
              }}
            </span>
          </label>
          <div class="w-px h-3 bg-n-weak rounded-lg ltr:ml-1 rtl:mr-1" />
          <NextButton
            :label="$t('BULK_ACTION.CLEAR_SELECTION')"
            ghost
            class="!text-n-blue-11 !px-2"
            sm
            @click="allSelected = false"
          />
        </div>
        <div class="flex shrink-0 items-center gap-2">
          <BulkLabelActions button-size="sm" @assign="onAssignLabels" />
          <BulkLabelActions
            action="remove"
            :applied-labels="appliedLabelsForSelection"
            button-size="sm"
            @remove="onRemoveLabels"
          />
          <BulkUpdateActions
            :show-resolve="!showResolvedAction"
            :show-reopen="!showOpenAction"
            :show-snooze="!showSnoozedAction"
            button-size="sm"
            @update="onUpdateConversations"
          />
          <NextButton
            v-tooltip="$t('BULK_ACTION.DELETE.DELETE_SELECTED_TOOLTIP')"
            icon="i-lucide-trash-2"
            ruby
            sm
            ghost
            @click="openDeleteConversationsDialog"
          />
          <BulkAgentActions
            :selected-inboxes="selectedInboxes"
            :conversation-count="conversations.length"
            button-size="sm"
            @select="onAssignAgent"
          />
          <BulkTeamActions
            :conversation-count="conversations.length"
            button-size="sm"
            @select="onAssignTeam"
          />
        </div>
      </div>
    </div>
  </Transition>
  <Dialog
    ref="deleteConversationsDialogRef"
    type="alert"
    :title="
      $t('BULK_ACTION.DELETE.TITLE', {
        conversationCount:
          pendingDeleteConversationIds.length || conversations.length,
      })
    "
    :description="$t('BULK_ACTION.DELETE.DESCRIPTION')"
    :confirm-button-label="$t('BULK_ACTION.DELETE.CONFIRM')"
    :is-loading="isDeletingConversations"
    @confirm="confirmDeleteConversations"
    @close="clearPendingDeleteConversations"
  />
  <woot-modal
    v-model:show="showCustomTimeSnoozeModal"
    :on-close="hideCustomSnoozeModal"
  >
    <CustomSnoozeModal
      @close="hideCustomSnoozeModal"
      @choose-time="customSnoozeTime"
    />
  </woot-modal>
</template>
