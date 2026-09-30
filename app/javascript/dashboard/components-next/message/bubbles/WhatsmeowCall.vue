<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useMessageContext } from '../provider';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import BaseBubble from './Base.vue';

const { t, locale } = useI18n();
const store = useStore();
const { contentAttributes, conversationId, createdAt } = useMessageContext();
const callTime = computed(() => new Date(createdAt.value * 1000));
const readableTime = computed(() =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(callTime.value)
);
const call = computed(() =>
  useCamelCase(
    contentAttributes.value.whatsmeowCall ||
      contentAttributes.value.whatsmeow_call
  )
);
const missed = computed(
  () => call.value.direction === 'incoming' && call.value.status !== 'completed'
);
const title = computed(() =>
  t(
    `CONVERSATION.WHATSMEOW_CALL.${call.value.video ? 'VIDEO' : 'VOICE'}${missed.value ? '_MISSED' : ''}`
  )
);
const detail = computed(() => {
  if (call.value.status === 'completed') {
    const seconds = call.value.durationSeconds;
    return seconds < 60
      ? t('CONVERSATION.WHATSMEOW_CALL.SECONDS', { count: seconds })
      : t('CONVERSATION.WHATSMEOW_CALL.MINUTES_SECONDS', {
          minutes: Math.floor(seconds / 60),
          seconds: seconds % 60,
        });
  }
  return t(
    `CONVERSATION.WHATSMEOW_CALL.${call.value.status === 'declined' ? 'DECLINED' : 'UNANSWERED'}`
  );
});
const canCallBack = computed(
  () =>
    store.getters.getConversationById(conversationId.value)
      ?.whatsmeow_call_available === true
);
const callBack = () =>
  emitter.emit(BUS_EVENTS.WHATSMEOW_START_CALL, {
    conversationId: conversationId.value,
    video: call.value.video,
  });
</script>

<template>
  <BaseBubble
    hide-meta
    class="!p-3 w-72 max-w-full"
    data-bubble-name="whatsmeow-call"
  >
    <button
      type="button"
      class="flex w-full items-center gap-3 rounded-lg text-left focus-visible:ring-2 focus-visible:ring-n-brand"
      :disabled="!canCallBack"
      :aria-label="t('CONVERSATION.WHATSMEOW_CALL.CALL_BACK')"
      @click="callBack"
    >
      <span
        class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-alpha-2"
        :class="missed ? 'text-n-ruby-11' : 'text-n-slate-12'"
      >
        <span
          class="size-5"
          :class="
            call.video
              ? 'i-lucide-video'
              : missed
                ? 'i-lucide-phone-missed'
                : call.direction === 'incoming'
                  ? 'i-lucide-phone-incoming'
                  : 'i-lucide-phone-outgoing'
          "
        />
      </span>
      <span class="flex min-w-0 flex-col gap-1">
        <span
          class="text-sm font-semibold"
          :class="{ 'text-n-ruby-11': missed }"
          >{{ title }}</span
        >
        <span class="text-xs text-n-slate-11">{{ detail }}</span>
        <span v-if="canCallBack" class="text-xs text-n-slate-11">{{
          t('CONVERSATION.WHATSMEOW_CALL.CLICK_TO_RETURN')
        }}</span>
      </span>
    </button>
    <div class="mt-2 flex justify-end">
      <time
        class="text-xs text-n-slate-11"
        :datetime="callTime.toISOString()"
        >{{ readableTime }}</time
      >
    </div>
  </BaseBubble>
</template>
