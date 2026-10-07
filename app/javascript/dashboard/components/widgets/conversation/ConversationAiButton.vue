<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';

const props = defineProps({ chat: { type: Object, required: true } });
const { t } = useI18n();
const state = ref(null);
const busy = ref(false);
const open = ref(false);
let request = 0;
const active = computed(
  () => state.value?.status === 'active' && state.value?.enabled
);
const label = computed(() => {
  if (!state.value?.enabled) return t('MARCOX_AI.CONVERSATION.DISABLED');
  if (state.value.processing && active.value)
    return t('MARCOX_AI.CONVERSATION.WORKING');
  return t(
    active.value ? 'MARCOX_AI.CONVERSATION.ON' : 'MARCOX_AI.CONVERSATION.OFF'
  );
});
const items = computed(() => [
  {
    action: active.value ? 'pause' : 'resume',
    value: 'toggle',
    icon: active.value ? 'i-lucide-pause' : 'i-lucide-play',
    label: t(
      active.value
        ? 'MARCOX_AI.CONVERSATION.PAUSE'
        : 'MARCOX_AI.CONVERSATION.RESUME'
    ),
    disabled: busy.value || !state.value?.enabled,
  },
  {
    action: 'reply_now',
    value: 'reply_now',
    icon: 'i-lucide-message-circle',
    label: t('MARCOX_AI.CONVERSATION.CONTINUE'),
    disabled:
      busy.value ||
      !state.value?.enabled ||
      ['resolved', 'snoozed'].includes(props.chat.status),
  },
  {
    action: 'handoff',
    value: 'handoff',
    icon: 'i-lucide-hand',
    label: t('MARCOX_AI.CONVERSATION.HUMAN'),
    disabled: busy.value,
  },
]);
watch(
  () => props.chat.id,
  async id => {
    request += 1;
    const current = request;
    state.value = props.chat.marcosx_ai || null;
    open.value = false;
    busy.value = false;
    if (!id) return;
    try {
      const { data } = await MarcosxAiAPI.getConversationState(id);
      if (request === current) state.value = data.state;
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
const act = async ({ action }) => {
  open.value = false;
  const { id } = props.chat;
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
    const notice = {
      resume: 'MARCOX_AI.CONVERSATION.RESUMED_OK',
      reply_now: 'MARCOX_AI.CONVERSATION.CONTINUE_OK',
    };
    useAlert(t(notice[action] || 'MARCOX_AI.CONVERSATION.PAUSED_OK'));
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
  <div
    v-if="state?.assistant_id"
    v-on-clickaway="() => (open = false)"
    class="relative"
  >
    <Button
      v-tooltip="state.reason || state.assistant_name"
      size="sm"
      variant="faded"
      :color="active ? 'teal' : 'slate'"
      :icon="
        state.processing && active ? 'i-lucide-loader-circle' : 'i-lucide-bot'
      "
      :label="label"
      :is-loading="busy"
      :disabled="busy"
      :aria-label="
        t('MARCOX_AI.CONVERSATION.LABEL', {
          name: state.assistant_name,
          status: label,
        })
      "
      :aria-expanded="open"
      @click="open = !open"
    />
    <DropdownMenu
      v-if="open"
      :menu-items="items"
      class="right-0 top-full z-50 mt-2 min-w-56"
      @action="act"
    />
  </div>
</template>
