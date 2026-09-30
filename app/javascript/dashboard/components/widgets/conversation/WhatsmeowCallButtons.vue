<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
  chat: { type: Object, required: true },
});
const { t } = useI18n();
const available = computed(
  () =>
    props.inbox.channel_type === 'Channel::Whatsmeow' &&
    props.chat.whatsmeow_call_available === true
);
const startCall = video =>
  emitter.emit(BUS_EVENTS.WHATSMEOW_START_CALL, {
    conversationId: props.chat.id,
    video,
  });
</script>

<template>
  <template v-if="available">
    <NextButton
      v-tooltip.bottom="t('CONVERSATION.WHATSMEOW_CALL.VOICE')"
      sm
      ghost
      slate
      icon="i-lucide-phone"
      :aria-label="t('CONVERSATION.WHATSMEOW_CALL.VOICE')"
      @click="startCall(false)"
    />
    <NextButton
      v-tooltip.bottom="t('CONVERSATION.WHATSMEOW_CALL.VIDEO')"
      sm
      ghost
      slate
      icon="i-lucide-video"
      :aria-label="t('CONVERSATION.WHATSMEOW_CALL.VIDEO')"
      @click="startCall(true)"
    />
  </template>
</template>
