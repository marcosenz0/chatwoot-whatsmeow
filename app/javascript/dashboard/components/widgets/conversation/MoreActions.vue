<script setup>
import { computed, onUnmounted, ref, watch } from 'vue';
import { useToggle } from '@vueuse/core';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import EmailTranscriptModal from './EmailTranscriptModal.vue';
import ResolveAction from '../../buttons/ResolveAction.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';

import {
  CMD_MUTE_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

// No props needed as we're getting currentChat from the store directly
const store = useStore();
const { t } = useI18n();

const [showEmailActionsModal, toggleEmailModal] = useToggle(false);
const [showActionsDropdown, toggleDropdown] = useToggle(false);

const currentChat = computed(() => store.getters.getSelectedChat);
const marcosxAiState = ref(null);
const isMarcosxAiActionLoading = ref(false);

const isMarcosxAiLinked = computed(() => !!marcosxAiState.value?.assistant_id);
const shouldShowResumeAi = computed(() =>
  ['paused_by_agent', 'paused_by_human', 'handoff', 'error'].includes(
    marcosxAiState.value?.status
  )
);

const actionMenuItems = computed(() => {
  const items = [];

  if (isMarcosxAiLinked.value) {
    if (shouldShowResumeAi.value) {
      items.push({
        icon: 'i-lucide-play',
        label: 'Retomar MarcosX IA',
        action: 'marcosx_ai_resume',
        value: 'marcosx_ai_resume',
        disabled: isMarcosxAiActionLoading.value,
      });
    } else {
      items.push({
        icon: 'i-lucide-pause',
        label: 'Pausar MarcosX IA',
        action: 'marcosx_ai_pause',
        value: 'marcosx_ai_pause',
        disabled: isMarcosxAiActionLoading.value,
      });
    }

    items.push({
      icon: 'i-lucide-hand',
      label: 'Assumir atendimento',
      action: 'marcosx_ai_handoff',
      value: 'marcosx_ai_handoff',
      disabled: isMarcosxAiActionLoading.value,
    });
  }

  if (!currentChat.value.muted) {
    items.push({
      icon: 'i-lucide-volume-off',
      label: t('CONTACT_PANEL.MUTE_CONTACT'),
      action: 'mute',
      value: 'mute',
    });
  } else {
    items.push({
      icon: 'i-lucide-volume-1',
      label: t('CONTACT_PANEL.UNMUTE_CONTACT'),
      action: 'unmute',
      value: 'unmute',
    });
  }

  items.push({
    icon: 'i-lucide-share',
    label: t('CONTACT_PANEL.SEND_TRANSCRIPT'),
    action: 'send_transcript',
    value: 'send_transcript',
  });

  return items;
});

const fetchMarcosxAiState = async () => {
  const conversationId = currentChat.value?.id;
  if (!conversationId) {
    marcosxAiState.value = null;
    return;
  }

  try {
    const { data } = await MarcosxAiAPI.getConversationState(conversationId);
    marcosxAiState.value = data.state;
  } catch {
    marcosxAiState.value = null;
  }
};

const updateMarcosxAiState = async action => {
  const conversationId = currentChat.value?.id;
  if (!conversationId) return;

  isMarcosxAiActionLoading.value = true;
  try {
    const { data } = await MarcosxAiAPI.updateConversationState(
      conversationId,
      {
        action,
        reason: 'agent_action',
      }
    );
    marcosxAiState.value = data.state;
    useAlert(
      action === 'resume'
        ? 'MarcosX IA retomada.'
        : 'MarcosX IA pausada para atendimento humano.'
    );
  } catch {
    useAlert('Nao foi possivel atualizar a MarcosX IA.');
  } finally {
    isMarcosxAiActionLoading.value = false;
  }
};

const handleActionClick = ({ action }) => {
  toggleDropdown(false);

  if (action === 'marcosx_ai_pause') {
    updateMarcosxAiState('pause');
  } else if (action === 'marcosx_ai_resume') {
    updateMarcosxAiState('resume');
  } else if (action === 'marcosx_ai_handoff') {
    updateMarcosxAiState('handoff');
  } else if (action === 'mute') {
    store.dispatch('muteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
  } else if (action === 'unmute') {
    store.dispatch('unmuteConversation', currentChat.value.id);
    useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
  } else if (action === 'send_transcript') {
    toggleEmailModal();
  }
};

// These functions are needed for the event listeners
const mute = () => {
  store.dispatch('muteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.MUTED_SUCCESS'));
};

const unmute = () => {
  store.dispatch('unmuteConversation', currentChat.value.id);
  useAlert(t('CONTACT_PANEL.UNMUTED_SUCCESS'));
};

emitter.on(CMD_MUTE_CONVERSATION, mute);
emitter.on(CMD_UNMUTE_CONVERSATION, unmute);
emitter.on(CMD_SEND_TRANSCRIPT, toggleEmailModal);

watch(
  () => currentChat.value?.id,
  () => fetchMarcosxAiState(),
  { immediate: true }
);

onUnmounted(() => {
  emitter.off(CMD_MUTE_CONVERSATION, mute);
  emitter.off(CMD_UNMUTE_CONVERSATION, unmute);
  emitter.off(CMD_SEND_TRANSCRIPT, toggleEmailModal);
});
</script>

<template>
  <div class="relative flex items-center gap-2 actions--container">
    <ResolveAction
      :conversation-id="currentChat.id"
      :status="currentChat.status"
    />
    <div
      v-on-clickaway="() => toggleDropdown(false)"
      class="relative flex items-center group"
    >
      <ButtonV4
        v-tooltip="$t('CONVERSATION.HEADER.MORE_ACTIONS')"
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-more-vertical"
        class="rounded-md group-hover:bg-n-alpha-2"
        @click="toggleDropdown()"
      />
      <DropdownMenu
        v-if="showActionsDropdown"
        :menu-items="actionMenuItems"
        class="mt-1 ltr:right-0 rtl:left-0 top-full"
        @action="handleActionClick"
      />
    </div>
    <EmailTranscriptModal
      v-if="showEmailActionsModal"
      :show="showEmailActionsModal"
      :current-chat="currentChat"
      @cancel="toggleEmailModal"
    />
  </div>
</template>
