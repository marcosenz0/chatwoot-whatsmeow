<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({ chat: { type: Object, required: true } });
const { t } = useI18n();
const active = computed(
  () =>
    props.chat.marcosx_ai?.status === 'active' &&
    props.chat.marcosx_ai.enabled &&
    props.chat.marcosx_ai.available &&
    !['resolved', 'snoozed'].includes(props.chat.status)
);
</script>

<template>
  <span
    v-if="active"
    v-tooltip.top="chat.marcosx_ai.assistant_name"
    class="inline-flex shrink-0 items-center gap-1 rounded bg-n-teal-3 px-1 py-0.5 text-[10px] font-medium normal-case leading-3 text-n-teal-11"
  >
    <span class="i-lucide-bot size-3" aria-hidden="true" />
    {{ t('MARCOX_AI.CONVERSATION.ON') }}
  </span>
</template>
