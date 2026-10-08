<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
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
let generation = 0;
const reset = () => {
  generation += 1;
  messages.value = [];
  files.value = [];
  error.value = '';
  sending.value = false;
};
watch(selectedId, reset);
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
    !agent.value ||
    (!message.value.trim() && !files.value.length)
  )
    return;
  const currentGeneration = generation;
  const agentId = agent.value.id;
  const history = messages.value.map(item => ({
    role: item.role,
    content: item.context || item.content,
  }));
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
    const body = new FormData();
    body.append('assistant[message]', content);
    history.forEach(item => {
      body.append(`assistant[history][][role]`, item.role);
      body.append(`assistant[history][][content]`, item.content);
    });
    attachments.forEach(file => body.append('files[]', file));
    const { data } = await MarcosxAiAPI.runPlayground(agentId, body);
    if (currentGeneration !== generation) return;
    messages.value[messages.value.length - 1].context = data.user_context;
    messages.value.push({
      role: 'assistant',
      content: data.response,
      plan: data.plan,
      name: agent.value.name,
    });
  } catch (failure) {
    if (currentGeneration === generation)
      error.value =
        failure.response?.data?.error || t('MARCOX_AI.PLAYGROUND.ERROR');
  } finally {
    if (currentGeneration === generation) sending.value = false;
    await nextTick();
    if (thread.value) thread.value.scrollTop = thread.value.scrollHeight;
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
        <Button
          variant="ghost"
          color="slate"
          icon="i-lucide-rotate-ccw"
          :label="t('MARCOX_AI.PLAYGROUND.RESET')"
          @click="reset"
        />
      </div>
      <p class="mt-2 text-sm text-n-slate-11">
        {{ t('MARCOX_AI.PLAYGROUND.BODY') }}
      </p>
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
        v-if="!messages.length"
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
        :disabled="sending || !agent"
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
          :disabled="sending || !agent || (!message.trim() && !files.length)"
        />
      </div>
    </form>
  </section>
</template>
