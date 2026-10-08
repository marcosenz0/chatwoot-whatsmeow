<script setup>
import { ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';

const props = defineProps({ agentId: { type: Number, required: true } });
const route = useRoute();
const { t } = useI18n();
const logs = ref(null);
const failed = ref(false);
const { run, isPending } = useAbortableRequest();
let request = 0;
const load = async () => {
  request += 1;
  const current = request;
  const id = props.agentId;
  failed.value = false;
  try {
    const result = await run(signal => MarcosxAiAPI.getLogs(id, { signal }));
    if (result && current === request) logs.value = result.data.logs;
  } catch (error) {
    if (current !== request) return;
    failed.value = true;
    useAlert(error.response?.data?.error || t('MARCOX_AI.ERROR'));
  }
};
watch(
  () => props.agentId,
  () => {
    logs.value = null;
    load();
  },
  { immediate: true }
);
const eventLabel = event =>
  ({
    response_generated: 'GENERATED',
    response_sent: 'SENT',
    handoff: 'HANDOFF',
    response_failed: 'FAILED',
    analysis_ready: 'ANALYSIS',
  })[event] || 'EVENT';
</script>

<template>
  <section class="min-h-0 min-w-0 flex-1 overflow-y-auto px-6 py-6 xl:px-10">
    <div class="mb-6 flex flex-wrap items-start justify-between gap-4">
      <div>
        <h3 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ t('MARCOX_AI.TABS.ACTIVITY') }}
        </h3>
        <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
          {{ t('MARCOX_AI.ACTIVITY.BODY') }}
        </p>
      </div>
      <Button
        icon="i-lucide-refresh-cw"
        variant="outline"
        color="slate"
        :label="t('MARCOX_AI.REFRESH')"
        :is-loading="isPending"
        @click="load"
      />
    </div>
    <p v-if="failed" class="text-sm text-n-ruby-11">
      {{ t('MARCOX_AI.ERROR') }}
    </p>
    <div v-else-if="!logs" class="flex justify-center py-12"><Spinner /></div>
    <div v-else class="overflow-x-auto rounded-xl border border-n-weak">
      <p v-if="!logs.length" class="p-8 text-center text-sm text-n-slate-11">
        {{ t('MARCOX_AI.ACTIVITY.EMPTY') }}
      </p>
      <table v-else class="w-full text-start text-sm">
        <thead class="border-b border-n-weak text-n-slate-11">
          <tr>
            <th
              v-for="key in ['EVENT', 'CONVERSATION', 'WHEN']"
              :key="key"
              class="p-4 text-start font-medium"
            >
              {{ t(`MARCOX_AI.ACTIVITY.${key}`) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="log in logs"
            :key="log.id"
            class="border-b border-n-weak last:border-0"
          >
            <td class="p-4">
              <span
                :class="
                  log.status === 'error' ? 'text-n-ruby-11' : 'text-n-slate-12'
                "
              >
                {{ t(`MARCOX_AI.ACTIVITY.${eventLabel(log.event)}`) }}
              </span>
              <p
                v-if="log.error"
                class="mb-0 mt-1 max-w-sm break-words text-xs text-n-ruby-11"
              >
                {{ log.error }}
              </p>
            </td>
            <td class="p-4">
              <RouterLink
                v-if="log.conversation_id"
                :to="{
                  name: 'inbox_conversation',
                  params: {
                    accountId: route.params.accountId,
                    conversation_id: log.conversation_id,
                  },
                }"
                class="text-n-blue-11"
              >
                {{ `#${log.conversation_id}` }}
              </RouterLink>
            </td>
            <td class="whitespace-nowrap p-4 text-n-slate-11">
              {{ new Date(log.created_at).toLocaleString() }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
