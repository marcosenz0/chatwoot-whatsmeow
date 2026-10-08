<script setup>
import { computed, ref, watch } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AiSelect from 'dashboard/routes/dashboard/captain/components/AiSelect.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';

const props = defineProps({
  chat: { type: Object, required: true },
  state: { type: Object, default: null },
  assistants: { type: Array, default: () => [] },
});
const emit = defineEmits(['updated']);
const { t } = useI18n();
const dialog = ref(null);
const visible = ref(false);
const working = ref(false);
const assistantId = ref(null);
const analysis = ref({ status: 'idle' });
const parts = ref([]);
const { run, abort } = useAbortableRequest();
const selected = computed(() =>
  props.assistants.find(item => item.id === assistantId.value)
);
const options = computed(() =>
  props.assistants.map(item => ({
    value: item.id,
    label: item.name,
    description: item.model,
    icon: 'i-lucide-bot',
  }))
);
const active = computed(
  () => props.state?.status === 'active' && props.state.enabled
);
const available = computed(
  () =>
    selected.value?.enabled &&
    !['resolved', 'snoozed'].includes(props.chat.status)
);
const processing = computed(() => analysis.value.status === 'processing');
const notifyError = error =>
  useAlert(error.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR'));
const setReport = report => {
  analysis.value = report;
  parts.value = [...(report.plan?.messages || [])];
};
const fetchReport = async () => {
  const { id } = props.chat;
  try {
    const result = await run(signal =>
      MarcosxAiAPI.getConversationAnalysis(id, { signal })
    );
    if (result && visible.value && id === props.chat.id)
      setReport(result.data.analysis);
  } catch (error) {
    notifyError(error);
  }
};
useIntervalFn(() => {
  if (visible.value && processing.value) fetchReport();
}, 2500);
const close = () => {
  visible.value = false;
  abort();
};
const open = () => {
  assistantId.value =
    props.state?.assistant_id ||
    props.assistants.find(item => item.enabled)?.id ||
    null;
  setReport({ status: 'idle' });
  visible.value = true;
  dialog.value.open();
  fetchReport();
};
watch(
  () => props.chat.id,
  () => {
    dialog.value?.close();
    close();
    working.value = false;
  }
);
watch(
  () => props.state?.assistant_id,
  id => {
    if (visible.value && id) assistantId.value = id;
  }
);
const act = async action => {
  const { id } = props.chat;
  working.value = true;
  try {
    const { data } = await MarcosxAiAPI.updateConversationState(id, {
      action,
      reason: 'agent_action',
      ...(assistantId.value !== props.state?.assistant_id
        ? { assistant_id: assistantId.value }
        : {}),
    });
    if (id !== props.chat.id) return;
    emit('updated', data.state);
    if (action === 'select') setReport({ status: 'idle' });
    useAlert(
      t(
        action === 'resume'
          ? 'MARCOX_AI.CONVERSATION.RESUMED_OK'
          : 'MARCOX_AI.CONVERSATION.PAUSED_OK'
      )
    );
  } catch (error) {
    if (id === props.chat.id) notifyError(error);
  } finally {
    if (id === props.chat.id) working.value = false;
  }
};
const selectAssistant = id => {
  assistantId.value = id;
  act('select');
};
const analyze = async () => {
  const { id } = props.chat;
  working.value = true;
  abort();
  try {
    const { data } = await MarcosxAiAPI.analyzeConversation(
      id,
      assistantId.value
    );
    if (id !== props.chat.id) return;
    setReport(data.analysis);
    const result = await MarcosxAiAPI.getConversationState(id);
    if (id === props.chat.id) emit('updated', result.data.state);
  } catch (error) {
    if (id === props.chat.id) notifyError(error);
  } finally {
    if (id === props.chat.id) working.value = false;
  }
};
const send = async () => {
  const { id } = props.chat;
  working.value = true;
  try {
    const { data } = await MarcosxAiAPI.sendConversationAnalysis(
      id,
      analysis.value.id,
      parts.value
    );
    if (id !== props.chat.id) return;
    analysis.value = { ...analysis.value, status: 'sent' };
    emit('updated', data.state);
    useAlert(t('MARCOX_AI.ANALYSIS.SENT'));
  } catch (error) {
    if (id === props.chat.id) {
      notifyError(error);
      fetchReport();
    }
  } finally {
    if (id === props.chat.id) working.value = false;
  }
};
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="3xl"
    overflow-y-auto
    :title="t('MARCOX_AI.CONVERSATION.PANEL_TITLE')"
    :description="t('MARCOX_AI.CONVERSATION.PANEL_HINT')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="close"
  >
    <div class="space-y-5">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-end">
        <div class="min-w-0 flex-1">
          <p class="mb-2 text-sm font-medium text-n-slate-12">
            {{ t('MARCOX_AI.CONVERSATION.SELECT_AGENT') }}
          </p>
          <AiSelect
            :model-value="assistantId || ''"
            :options="options"
            :label="t('MARCOX_AI.CONVERSATION.SELECT_AGENT')"
            :placeholder="t('MARCOX_AI.CONVERSATION.SELECT_AGENT')"
            :teleport="false"
            :disabled="working || processing"
            @update:model-value="selectAssistant"
          />
        </div>
        <Button
          type="button"
          :icon="active ? 'i-lucide-pause' : 'i-lucide-play'"
          :color="active ? 'slate' : 'teal'"
          :label="
            t(
              active
                ? 'MARCOX_AI.CONVERSATION.PAUSE'
                : 'MARCOX_AI.CONVERSATION.RESUME'
            )
          "
          :disabled="working || processing || !available"
          @click="act(active ? 'pause' : 'resume')"
        />
      </div>
      <p v-if="!assistants.length" class="text-sm text-n-slate-11">
        {{ t('MARCOX_AI.CONVERSATION.NO_AGENT') }}
      </p>
      <p
        v-else-if="selected && !selected.enabled"
        class="text-sm text-n-amber-11"
      >
        {{ t('MARCOX_AI.CONVERSATION.GLOBAL_PAUSED') }}
      </p>
      <div
        class="rounded-lg bg-n-alpha-1 p-3 text-xs leading-5 text-n-slate-11"
      >
        {{ t('MARCOX_AI.CONVERSATION.FUTURE_ONLY') }}
      </div>
      <div
        class="flex items-center justify-between gap-3 border-t border-n-weak pt-5"
      >
        <div>
          <h4 class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t('MARCOX_AI.ANALYSIS.TITLE') }}
          </h4>
          <p class="mb-0 mt-1 text-xs text-n-slate-11">
            {{ t('MARCOX_AI.ANALYSIS.HINT') }}
          </p>
        </div>
        <Button
          type="button"
          icon="i-lucide-scan-text"
          variant="outline"
          color="slate"
          :label="t('MARCOX_AI.ANALYSIS.ANALYZE')"
          :is-loading="working || processing"
          :disabled="working || processing || !available"
          @click="analyze"
        />
      </div>
      <p
        v-if="processing"
        class="flex items-center gap-2 text-sm text-n-slate-11"
      >
        <span class="i-lucide-loader-circle size-4 animate-spin" />{{
          t('MARCOX_AI.ANALYSIS.PROCESSING')
        }}
      </p>
      <p
        v-if="['outdated', 'failed', 'sent'].includes(analysis.status)"
        class="rounded-lg bg-n-alpha-1 p-3 text-sm text-n-slate-11"
      >
        {{ t(`MARCOX_AI.ANALYSIS.${analysis.status.toUpperCase()}`) }}
      </p>
      <div
        v-if="analysis.status === 'ready'"
        class="max-h-[40vh] space-y-4 overflow-y-auto pe-2"
      >
        <p class="text-xs text-n-slate-10">
          {{
            t('MARCOX_AI.ANALYSIS.COUNT', { count: analysis.messages_count })
          }}
        </p>
        <div class="rounded-lg border border-n-weak p-4">
          <h4 class="m-0 text-xs font-semibold text-n-slate-12">
            {{ t('MARCOX_AI.ANALYSIS.SUMMARY') }}
          </h4>
          <p
            class="mb-0 mt-2 whitespace-pre-line text-sm leading-6 text-n-slate-11"
          >
            {{ analysis.summary }}
          </p>
          <h4 class="mb-0 mt-4 text-xs font-semibold text-n-slate-12">
            {{ t('MARCOX_AI.ANALYSIS.NEXT_STEP') }}
          </h4>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ analysis.next_step }}
          </p>
        </div>
        <h4 class="text-sm font-semibold text-n-slate-12">
          {{ t('MARCOX_AI.ANALYSIS.DRAFT') }}
        </h4>
        <label v-for="(_, index) in parts" :key="index" class="block">
          <span class="mb-2 block text-xs text-n-slate-11">{{
            t('MARCOX_AI.ANALYSIS.PART', { number: index + 1 })
          }}</span>
          <textarea
            v-model="parts[index]"
            rows="3"
            class="reset-base !mb-0 w-full resize-y rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm text-n-slate-12"
          />
        </label>
        <p v-if="analysis.plan.reaction" class="text-sm text-n-slate-11">
          {{
            t('MARCOX_AI.PLAYGROUND.REACTION', {
              emoji: analysis.plan.reaction,
            })
          }}
        </p>
        <p v-if="analysis.plan.handoff" class="text-sm text-n-amber-11">
          {{
            t('MARCOX_AI.PLAYGROUND.HANDOFF', {
              reason: analysis.plan.handoff_reason,
            })
          }}
        </p>
      </div>
    </div>
    <template #footer>
      <div
        class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak pt-4"
      >
        <Button
          type="button"
          variant="ghost"
          color="slate"
          icon="i-lucide-hand"
          :label="t('MARCOX_AI.CONVERSATION.HUMAN')"
          :disabled="working || !state?.assistant_id"
          @click="act('handoff')"
        />
        <div class="flex items-center gap-2">
          <Button
            type="button"
            variant="outline"
            color="slate"
            :label="t('MARCOX_AI.ANALYSIS.CLOSE')"
            @click="dialog.close()"
          />
          <Button
            v-if="analysis.status === 'ready'"
            type="button"
            icon="i-lucide-send"
            :label="t('MARCOX_AI.ANALYSIS.SEND')"
            :disabled="working || !available"
            :is-loading="working"
            @click="send"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>
