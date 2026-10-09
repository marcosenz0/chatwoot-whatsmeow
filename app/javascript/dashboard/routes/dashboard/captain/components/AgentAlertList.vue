<script setup>
import { ref, watch } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';

const props = defineProps({
  agentId: { type: Number, default: null },
  conversationId: { type: Number, default: null },
});
const { t } = useI18n();
const alerts = ref([]);
const { run } = useAbortableRequest();
const load = async () => {
  try {
    const result = await run(signal =>
      MarcosxAiAPI.getAlerts(props.agentId, props.conversationId, { signal })
    );
    if (result) alerts.value = result.data.alerts;
  } catch (error) {
    useAlert(error.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR'));
  }
};
watch(() => [props.agentId, props.conversationId], load, { immediate: true });
useIntervalFn(load, 5000);
const resolve = async id => {
  try {
    await MarcosxAiAPI.resolveAlert(id);
    await load();
  } catch (error) {
    useAlert(error.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR'));
  }
};
</script>

<template>
  <div class="space-y-3">
    <h4 class="m-0 text-sm font-semibold">
      {{ t('MARCOX_AI.AUTOMATION.PENDING') }}
    </h4>
    <p class="text-xs text-n-slate-11">
      {{ t('MARCOX_AI.AUTOMATION.RESOLVE_HINT') }}
    </p>
    <p v-if="!alerts.length" class="text-sm text-n-slate-11">
      {{ t('MARCOX_AI.AUTOMATION.NO_ALERTS') }}
    </p>
    <div
      v-for="alert in alerts"
      :key="alert.id"
      class="space-y-2 rounded-lg border border-n-weak p-3"
    >
      <p class="m-0 text-sm font-medium">
        #{{ alert.conversation_id }} · {{ alert.contact }} · {{ alert.name }}
      </p>
      <p class="m-0 text-xs text-n-slate-11">{{ alert.reason }}</p>
      <p class="m-0 text-xs text-n-slate-11">
        {{ t(`MARCOX_AI.AUTOMATION.STATUS_${alert.status.toUpperCase()}`) }}
      </p>
      <p
        v-for="delivery in alert.deliveries"
        :key="delivery.id"
        class="m-0 text-xs"
        :class="
          delivery.status === 'failed' ? 'text-n-ruby-11' : 'text-n-slate-11'
        "
      >
        {{ delivery.recipient }} ·
        {{
          t(`MARCOX_AI.AUTOMATION.DELIVERY_${delivery.status.toUpperCase()}`)
        }}
        {{ delivery.error }}
      </p>
      <Button
        v-if="alert.status === 'open'"
        size="sm"
        variant="outline"
        :label="t('MARCOX_AI.AUTOMATION.RESOLVE')"
        @click="resolve(alert.id)"
      />
    </div>
  </div>
</template>
