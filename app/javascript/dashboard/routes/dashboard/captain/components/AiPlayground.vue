<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AiSelect from './AiSelect.vue';

const props = defineProps({
  agents: { type: Array, default: () => [] },
  agentId: { type: Number, default: null },
  embedded: { type: Boolean, default: false },
});
const { t } = useI18n();
const selectedId = ref(props.agentId || props.agents[0]?.id || null);
const agent = computed(() =>
  props.agents.find(item => item.id === Number(selectedId.value))
);
const message = ref('');
const messages = ref([]);
const files = ref([]);
const input = ref(null);
const thread = ref(null);
const sending = ref(false);
const error = ref('');
const eventType = ref('message');
const sessionId = ref(null);
const sessions = ref([]);
const historyPage = ref(1);
const historyTotal = ref(0);
const historyLoading = ref(false);
const historyDialog = ref(null);
const loading = ref(false);
let generation = 0;
const reset = () => {
  generation += 1;
  messages.value = [];
  files.value = [];
  error.value = '';
  sending.value = false;
  message.value = '';
  sessionId.value = null;
};
const scrollToEnd = async () => {
  await nextTick();
  if (thread.value) thread.value.scrollTop = thread.value.scrollHeight;
};
const loadSession = async id => {
  reset();
  const currentGeneration = generation;
  loading.value = true;
  try {
    const { data } = await MarcosxAiAPI.getTestSession(selectedId.value, id);
    if (currentGeneration !== generation) return;
    sessionId.value = data.session.id;
    messages.value = data.session.messages;
    sending.value = data.session.processing;
    error.value = data.session.error || '';
    historyDialog.value?.close();
    await scrollToEnd();
  } catch (failure) {
    if (currentGeneration === generation)
      error.value =
        failure.response?.data?.error || t('MARCOX_AI.PLAYGROUND.ERROR');
  } finally {
    if (currentGeneration === generation) loading.value = false;
  }
};
const listSessions = async () => {
  const id = selectedId.value;
  const page = historyPage.value;
  historyLoading.value = true;
  try {
    const { data } = await MarcosxAiAPI.getTestSessions(id, page);
    if (id !== selectedId.value || page !== historyPage.value) return;
    sessions.value = data.sessions;
    historyTotal.value = data.total;
  } finally {
    if (id === selectedId.value && page === historyPage.value)
      historyLoading.value = false;
  }
};
const showHistory = async () => {
  try {
    historyPage.value = 1;
    await listSessions();
    historyDialog.value.open();
  } catch (failure) {
    error.value =
      failure.response?.data?.error || t('MARCOX_AI.PLAYGROUND.ERROR');
  }
};
watch(
  selectedId,
  async () => {
    reset();
    sessions.value = [];
    historyPage.value = 1;
    loading.value = true;
    const currentGeneration = generation;
    if (!selectedId.value) {
      loading.value = false;
      return;
    }
    try {
      await listSessions();
      if (currentGeneration === generation && sessions.value.length)
        await loadSession(sessions.value[0].id);
    } catch (failure) {
      if (currentGeneration === generation)
        error.value =
          failure.response?.data?.error || t('MARCOX_AI.PLAYGROUND.ERROR');
    } finally {
      if (currentGeneration === generation) loading.value = false;
    }
  },
  { immediate: true }
);
const changeHistoryPage = async step => {
  historyPage.value += step;
  try {
    await listSessions();
  } catch (failure) {
    error.value =
      failure.response?.data?.error || t('MARCOX_AI.PLAYGROUND.ERROR');
  }
};
useIntervalFn(async () => {
  if (!sending.value || !sessionId.value) return;
  const id = sessionId.value;
  const currentGeneration = generation;
  try {
    const { data } = await MarcosxAiAPI.getTestSession(selectedId.value, id);
    if (currentGeneration !== generation || id !== sessionId.value) return;
    messages.value = data.session.messages;
    sending.value = data.session.processing;
    error.value = data.session.error || '';
    await scrollToEnd();
  } catch {
    /* Keep the in-flight response; the request or next poll reports its outcome. */
  }
}, 5000);
watch(
  () => props.agentId,
  id => {
    if (id) selectedId.value = id;
  }
);
const attach = event => {
  const selected = [...event.target.files];
  if (
    selected.length > 3 ||
    selected.some(file => file.size > 25 * 1024 * 1024)
  )
    error.value = t('MARCOX_AI.PLAYGROUND.FILE_LIMIT');
  else {
    files.value = selected;
    error.value = '';
  }
  event.target.value = '';
};
const send = async () => {
  if (
    sending.value ||
    loading.value ||
    !agent.value ||
    (!message.value.trim() && !files.value.length)
  )
    return;
  const currentGeneration = generation;
  const agentId = agent.value.id;
  const content = message.value.trim() || t('MARCOX_AI.PLAYGROUND.ATTACH');
  const attachments = [...files.value];
  messages.value.push({
    role: 'user',
    content,
    files: attachments.map(file => file.name),
  });
  message.value = '';
  files.value = [];
  sending.value = true;
  error.value = '';
  try {
    if (!sessionId.value) {
      const { data } = await MarcosxAiAPI.createTestSession(agentId);
      if (currentGeneration !== generation) return;
      sessionId.value = data.session.id;
    }
    const body = new FormData();
    body.append('assistant[message]', content);
    body.append('assistant[event]', eventType.value);
    body.append('assistant[session_id]', sessionId.value);
    attachments.forEach(file => body.append('files[]', file));
    const { data } = await MarcosxAiAPI.runPlayground(agentId, body);
    if (currentGeneration !== generation) return;
    messages.value = data.session.messages;
  } catch (failure) {
    if (currentGeneration === generation)
      error.value =
        failure.response?.data?.error || t('MARCOX_AI.PLAYGROUND.ERROR');
  } finally {
    if (currentGeneration === generation) sending.value = false;
    await scrollToEnd();
  }
};
</script>

<template>
  <section
    class="flex h-full min-h-0 min-w-0 w-full flex-1 flex-col overflow-hidden bg-n-solid-1"
    :class="{ 'mx-auto max-w-5xl rounded-xl border border-n-weak': !embedded }"
  >
    <div class="border-b border-n-weak p-5">
      <div class="flex items-center justify-between gap-4">
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{ t('MARCOX_AI.PLAYGROUND.TITLE') }}
        </h2>
        <div class="flex flex-wrap gap-2">
          <Button
            type="button"
            variant="outline"
            color="slate"
            icon="i-lucide-messages-square"
            :label="t('MARCOX_AI.WORKSPACE.TEST_CHATS')"
            @click="showHistory"
          />
          <Button
            type="button"
            variant="ghost"
            color="slate"
            icon="i-lucide-rotate-ccw"
            :label="t('MARCOX_AI.PLAYGROUND.RESET')"
            :disabled="loading"
            @click="reset"
          />
        </div>
      </div>
      <p class="mt-2 text-sm text-n-slate-11">
        {{ t('MARCOX_AI.PLAYGROUND.BODY') }}
      </p>
      <AiSelect
        v-model="eventType"
        :options="
          ['message', 'missed_call'].map(value => ({
            value,
            label: t(`MARCOX_AI.AUTOMATION.EVENT_${value.toUpperCase()}`),
          }))
        "
        :label="t('MARCOX_AI.AUTOMATION.SIMULATE_EVENT')"
      />
      <label v-if="!embedded" class="mt-4 block text-sm text-n-slate-12">
        {{ t('MARCOX_AI.PLAYGROUND.SELECT') }}
        <AiSelect
          v-model="selectedId"
          :options="
            agents.map(item => ({
              value: item.id,
              label: item.name,
              description: item.config.model,
            }))
          "
          :label="t('MARCOX_AI.PLAYGROUND.SELECT')"
          class="mt-2"
      /></label>
      <p v-if="agent" class="mt-2 text-xs text-n-slate-11">
        {{ t('MARCOX_AI.PLAYGROUND.MODEL', { model: agent.config.model }) }}
      </p>
    </div>
    <div
      ref="thread"
      aria-live="polite"
      class="min-h-0 flex-1 space-y-4 overflow-y-auto p-5"
    >
      <div
        v-if="!messages.length && !loading"
        class="flex h-full min-h-44 flex-col items-center justify-center gap-4 text-center text-n-slate-11"
      >
        <span class="i-lucide-messages-square size-10 text-n-blue-9" />
        <p class="text-sm">
          {{
            t(
              agents.length
                ? 'MARCOX_AI.PLAYGROUND.START'
                : 'MARCOX_AI.NO_AGENTS'
            )
          }}
        </p>
      </div>
      <div
        v-for="(item, index) in messages"
        :key="index"
        class="flex"
        :class="item.role === 'user' ? 'justify-end' : 'justify-start'"
      >
        <div class="max-w-[85%] space-y-2">
          <p class="text-xs text-n-slate-11">
            {{
              item.role === 'user' ? t('MARCOX_AI.PLAYGROUND.YOU') : item.name
            }}
          </p>
          <div
            v-for="(part, partIndex) in item.plan?.messages || [item.content]"
            :key="partIndex"
            class="whitespace-pre-wrap break-words rounded-xl px-4 py-3 text-sm text-n-slate-12"
            :class="item.role === 'user' ? 'bg-n-blue-3' : 'bg-n-alpha-2'"
          >
            {{ part }}
          </div>
          <p
            v-for="file in item.files"
            :key="file"
            class="flex items-center gap-2 text-xs text-n-slate-11"
          >
            <span class="i-lucide-paperclip size-3" />{{ file }}
          </p>
          <p v-if="item.plan?.reaction" class="text-xs text-n-slate-11">
            {{
              t('MARCOX_AI.PLAYGROUND.REACTION', { emoji: item.plan.reaction })
            }}
          </p>
          <p
            v-for="alert in item.simulation?.alerts || []"
            :key="alert.id"
            class="text-xs text-n-slate-11"
          >
            {{
              t('MARCOX_AI.AUTOMATION.SIMULATED_ALERT', { name: alert.name })
            }}
          </p>
          <p v-if="item.simulation?.paused" class="text-xs text-n-amber-11">
            {{ t('MARCOX_AI.AUTOMATION.SIMULATED_PAUSE') }}
          </p>
          <p
            v-if="item.simulation?.recall_requested"
            class="text-xs text-n-slate-11"
          >
            {{ t('MARCOX_AI.AUTOMATION.SIMULATED_RECALL') }}
          </p>
          <p
            v-if="item.plan?.handoff"
            class="rounded-lg bg-n-amber-3 p-3 text-xs text-n-amber-11"
          >
            {{
              t('MARCOX_AI.PLAYGROUND.HANDOFF', {
                reason: item.plan.handoff_reason,
              })
            }}
          </p>
        </div>
      </div>
      <p v-if="sending" class="animate-pulse text-sm text-n-slate-11">
        {{ t('MARCOX_AI.PLAYGROUND.TYPING') }}
      </p>
    </div>
    <form class="space-y-3 border-t border-n-weak p-4" @submit.prevent="send">
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <div
        v-if="files.length"
        class="flex items-center justify-between text-xs text-n-slate-11"
      >
        <span>{{ files.map(file => file.name).join(', ') }}</span
        ><Button
          type="button"
          icon="i-lucide-x"
          variant="ghost"
          color="slate"
          size="xs"
          :aria-label="t('MARCOX_AI.PLAYGROUND.REMOVE_FILES')"
          @click="files = []"
        />
      </div>
      <textarea
        v-model="message"
        rows="2"
        :placeholder="t('MARCOX_AI.PLAYGROUND.PLACEHOLDER')"
        :disabled="sending || loading || !agent"
        class="!mb-0 w-full resize-none rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm"
        @keydown.enter.exact.prevent="send"
      />
      <div class="flex items-center justify-between">
        <input
          ref="input"
          type="file"
          multiple
          accept="image/*,audio/*,video/*,.pdf,.txt,.csv,.docx,.xlsx,.pptx"
          class="hidden"
          @change="attach"
        /><Button
          type="button"
          icon="i-lucide-paperclip"
          variant="ghost"
          color="slate"
          :label="t('MARCOX_AI.PLAYGROUND.ATTACH')"
          :disabled="sending || !agent"
          @click="input.click()"
        /><Button
          type="submit"
          icon="i-lucide-send"
          :label="t('MARCOX_AI.PLAYGROUND.SEND')"
          :is-loading="sending"
          :disabled="
            sending || loading || !agent || (!message.trim() && !files.length)
          "
        />
      </div>
    </form>
    <Dialog
      ref="historyDialog"
      :title="t('MARCOX_AI.WORKSPACE.TEST_CHATS')"
      :show-confirm-button="false"
      :cancel-button-label="t('MARCOX_AI.WORKSPACE.CLOSE')"
      width="2xl"
    >
      <div class="max-h-[60vh] space-y-2 overflow-y-auto">
        <p v-if="!sessions.length" class="text-sm text-n-slate-11">
          {{ t('MARCOX_AI.WORKSPACE.NO_CHATS') }}
        </p>
        <button
          v-for="chat in sessions"
          :key="chat.id"
          type="button"
          class="flex w-full items-center justify-between gap-3 rounded-xl border border-n-weak p-4 text-start hover:bg-n-alpha-2"
          @click="loadSession(chat.id)"
        >
          <span class="truncate text-sm text-n-slate-12">{{
            chat.title || t('MARCOX_AI.PLAYGROUND.RESET')
          }}</span>
          <span class="shrink-0 text-xs text-n-slate-11"
            >{{ chat.count }} ·
            {{ new Date(chat.updated_at).toLocaleDateString() }}</span
          >
        </button>
      </div>
      <div v-if="historyTotal > 25" class="flex items-center justify-end gap-3">
        <Button
          type="button"
          variant="ghost"
          icon="i-lucide-chevron-left"
          :disabled="historyLoading || historyPage === 1"
          :aria-label="t('MARCOX_AI.WORKSPACE.PREVIOUS')"
          @click="changeHistoryPage(-1)"
        />
        <span class="text-sm text-n-slate-11"
          >{{ historyPage }} / {{ Math.ceil(historyTotal / 25) }}</span
        >
        <Button
          type="button"
          variant="ghost"
          icon="i-lucide-chevron-right"
          :disabled="historyLoading || historyPage * 25 >= historyTotal"
          :aria-label="t('MARCOX_AI.WORKSPACE.NEXT')"
          @click="changeHistoryPage(1)"
        />
      </div>
    </Dialog>
  </section>
</template>
