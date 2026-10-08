<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import ConversationAiPanel from './ConversationAiPanel.vue';

const props = defineProps({ chat: { type: Object, required: true } });
const { t } = useI18n();
const state = ref(null);
const assistants = ref([]);
const busy = ref(false);
const panel = ref(null);
let request = 0;
const active = computed(
  () =>
    state.value?.status === 'active' &&
    state.value?.enabled &&
    state.value?.available
);
const label = computed(() => {
  if (state.value?.processing && active.value)
    return t('MARCOX_AI.CONVERSATION.WORKING');
  return t(
    active.value ? 'MARCOX_AI.CONVERSATION.ON' : 'MARCOX_AI.CONVERSATION.OFF'
  );
});
watch(
  () => props.chat.id,
  async id => {
    request += 1;
    const current = request;
    state.value = props.chat.marcosx_ai || null;
    assistants.value = [];
    busy.value = false;
    if (!id) return;
    try {
      const { data } = await MarcosxAiAPI.getConversationState(id);
      if (request !== current) return;
      state.value = data.state;
      assistants.value = data.assistants || [];
    } catch {
      if (request === current) state.value = null;
    }
  },
  { immediate: true }
);
watch(
  () => props.chat.marcosx_ai,
  value => {
    if (
      value &&
      (!state.value?.updated_at ||
        new Date(value.updated_at) >= new Date(state.value.updated_at))
    )
      state.value = value;
  }
);
const updateState = value => {
  request += 1;
  state.value = value;
};
const toggle = async () => {
  if (!state.value?.assistant_id || !state.value.available) {
    panel.value.open();
    return;
  }
  const { id } = props.chat;
  const action = active.value ? 'pause' : 'resume';
  request += 1;
  const current = request;
  busy.value = true;
  try {
    const { data } = await MarcosxAiAPI.updateConversationState(id, {
      action,
      reason: 'agent_action',
    });
    if (current !== request) return;
    state.value = data.state;
    useAlert(
      t(
        action === 'resume'
          ? 'MARCOX_AI.CONVERSATION.RESUMED_OK'
          : 'MARCOX_AI.CONVERSATION.PAUSED_OK'
      )
    );
  } catch (error) {
    if (current === request)
      useAlert(
        error.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR')
      );
  } finally {
    if (current === request) busy.value = false;
  }
};
</script>

<template>
  <div class="flex items-center gap-0.5">
    <Button
      v-tooltip="
        state?.assistant_name || t('MARCOX_AI.CONVERSATION.SELECT_AGENT')
      "
      size="sm"
      variant="faded"
      :color="active ? 'teal' : 'slate'"
      :icon="
        state?.processing && active ? 'i-lucide-loader-circle' : 'i-lucide-bot'
      "
      :label="label"
      :is-loading="busy"
      :disabled="busy"
      :aria-label="
        t('MARCOX_AI.CONVERSATION.LABEL', {
          name: state?.assistant_name || t('MARCOX_AI.TITLE'),
          status: label,
        })
      "
      @click="toggle"
    />
    <Button
      size="sm"
      variant="ghost"
      color="slate"
      icon="i-lucide-chevron-down"
      :aria-label="t('MARCOX_AI.CONVERSATION.PANEL_TITLE')"
      :disabled="busy"
      @click="panel.open()"
    />
    <ConversationAiPanel
      ref="panel"
      :chat="chat"
      :state="state"
      :assistants="assistants"
      @updated="updateState"
    />
  </div>
</template>
