<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import AiToggleRow from './AiToggleRow.vue';
import AiModelSelect from './AiModelSelect.vue';

const props = defineProps({
  agent: { type: Object, required: true },
  agents: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
  credentials: { type: Array, default: () => [] },
  catalogs: { type: Object, default: () => ({}) },
  defaultPrompt: { type: String, default: '' },
  canEdit: { type: Boolean, default: false },
  saving: { type: Boolean, default: false },
});
const emit = defineEmits(['save', 'cancel', 'delete', 'test', 'change']);
const { t } = useI18n();
const form = ref({});
const section = ref('identity');
const inboxSearch = ref('');
const sections = computed(() => [
  {
    id: 'identity',
    icon: 'i-lucide-bot',
    label: t('MARCOX_AI.EDITOR.IDENTITY'),
  },
  {
    id: 'prompt',
    icon: 'i-lucide-notebook-pen',
    label: t('MARCOX_AI.EDITOR.PROMPT'),
  },
  {
    id: 'inboxes',
    icon: 'i-lucide-inbox',
    label: t('MARCOX_AI.EDITOR.INBOXES'),
  },
  {
    id: 'behavior',
    icon: 'i-lucide-sliders-horizontal',
    label: t('MARCOX_AI.EDITOR.BEHAVIOR'),
  },
]);
watch(
  () => props.agent,
  agent => {
    form.value = JSON.parse(JSON.stringify(agent));
    section.value = 'identity';
  },
  { immediate: true }
);
watch(form, value => emit('change', value), { deep: true });
const modelOptions = computed(
  () => props.catalogs[form.value.config.provider]?.models || []
);
const model = computed(() =>
  modelOptions.value.find(item => item.id === form.value.config.model)
);
const connectionReady = computed(() =>
  props.credentials.some(
    item =>
      item.provider === form.value.config.provider &&
      item.enabled &&
      item.configured
  )
);
const providerOptions = [
  { id: 'openai', label: 'OpenAI' },
  { id: 'groq', label: 'Groq' },
  { id: 'gemini', label: 'Google Gemini' },
];
watch(
  () => form.value.config.provider,
  (provider, previous) => {
    if (!previous || provider === previous) return;
    const credential = props.credentials.find(
      item => item.provider === provider
    );
    form.value.config.model =
      credential?.model || props.catalogs[provider]?.models?.[0]?.id || '';
    form.value.config.auto_response_enabled = false;
  }
);
const visibleInboxes = computed(() =>
  props.inboxes.filter(inbox =>
    inbox.name.toLowerCase().includes(inboxSearch.value.toLowerCase())
  )
);
const ownerFor = inbox =>
  props.agents.find(
    agent => agent.id !== form.value.id && agent.inbox_ids.includes(inbox.id)
  );
const toggleInbox = inbox => {
  if (ownerFor(inbox)) return;
  const ids = form.value.inbox_ids;
  form.value.inbox_ids = ids.includes(inbox.id)
    ? ids.filter(id => id !== inbox.id)
    : [...ids, inbox.id];
};
const selectAll = () => {
  form.value.inbox_ids = props.inboxes
    .filter(inbox => !ownerFor(inbox))
    .map(inbox => inbox.id);
};
const mediaOptions = computed(() => [
  {
    key: 'process_images',
    icon: 'i-lucide-image',
    label: t('MARCOX_AI.EDITOR.IMAGES'),
    disabled: model.value?.vision === false,
  },
  {
    key: 'process_audio',
    icon: 'i-lucide-audio-lines',
    label: t('MARCOX_AI.EDITOR.AUDIO'),
    disabled: false,
  },
  {
    key: 'process_files',
    icon: 'i-lucide-file-text',
    label: t('MARCOX_AI.EDITOR.FILES'),
    disabled: model.value?.files === false,
  },
  {
    key: 'process_video',
    icon: 'i-lucide-video',
    label: t('MARCOX_AI.EDITOR.VIDEO'),
    disabled: model.value?.vision === false,
  },
]);
const channelLabel = inbox =>
  ({
    'Channel::Whatsmeow': 'WhatsApp Direct',
    'Channel::Whatsapp': 'WhatsApp',
    'Channel::TelegramPersonal': 'Telegram',
    'Channel::Telegram': 'Telegram Bot',
    'Channel::Instagram': 'Instagram',
    'Channel::WebWidget': 'Website',
    'Channel::Email': 'Email',
  })[inbox.channel_type] ||
  inbox.inbox_type ||
  inbox.name;
</script>

<template>
  <div
    class="flex min-h-0 flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
  >
    <div
      class="flex items-center justify-between gap-3 border-b border-n-weak px-6 py-5"
    >
      <div>
        <p class="m-0 text-xs text-n-slate-11">
          {{ t('MARCOX_AI.EDITOR.TITLE') }}
        </p>
        <h2 class="m-0 mt-1 text-lg font-semibold text-n-slate-12">
          {{ form.name || t('MARCOX_AI.EDITOR.NEW') }}
        </h2>
      </div>
      <Button
        :label="t('MARCOX_AI.CANCEL')"
        icon="i-lucide-x"
        variant="ghost"
        color="slate"
        @click="emit('cancel')"
      />
    </div>
    <div
      class="flex gap-1 overflow-x-auto border-b border-n-weak px-4 pt-2"
      role="tablist"
    >
      <button
        v-for="item in sections"
        :key="item.id"
        type="button"
        role="tab"
        :aria-selected="section === item.id"
        class="flex items-center gap-2 whitespace-nowrap border-b-2 px-3 py-3 text-xs font-medium"
        :class="
          section === item.id
            ? 'border-n-blue-9 text-n-blue-text'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="section = item.id"
      >
        <span :class="item.icon" class="size-4" />{{ item.label }}
      </button>
    </div>
    <form
      id="marcosx-agent-editor"
      class="min-h-0 flex-1 overflow-y-auto px-6 py-5"
      @submit.prevent="emit('save', form)"
    >
      <fieldset :disabled="!canEdit" class="m-0 min-w-0 border-0 p-0">
        <div v-show="section === 'identity'" class="space-y-5">
          <label class="block text-sm font-medium text-n-slate-12">
            {{ t('MARCOX_AI.EDITOR.NAME') }}
            <input
              v-model="form.name"
              required
              maxlength="120"
              :placeholder="t('MARCOX_AI.EDITOR.NAME_PLACEHOLDER')"
              class="!mb-0 mt-2 !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
            />
          </label>
          <label class="block text-sm font-medium text-n-slate-12">
            {{ t('MARCOX_AI.EDITOR.DESCRIPTION') }}
            <input
              v-model="form.description"
              :placeholder="t('MARCOX_AI.EDITOR.DESCRIPTION_PLACEHOLDER')"
              class="!mb-0 mt-2 !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
            />
          </label>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <label class="block text-sm font-medium text-n-slate-12">
              {{ t('MARCOX_AI.EDITOR.PROVIDER') }}
              <select
                v-model="form.config.provider"
                class="!mb-0 mt-2 !h-10 w-full rounded-lg border border-n-weak bg-n-background px-3 text-sm"
              >
                <option
                  v-for="provider in providerOptions"
                  :key="provider.id"
                  :value="provider.id"
                >
                  {{ provider.label }}
                </option>
              </select>
            </label>
            <label class="block text-sm font-medium text-n-slate-12">
              {{ t('MARCOX_AI.EDITOR.MODEL') }}
              <AiModelSelect
                v-model="form.config.model"
                :models="modelOptions"
                class="mt-2"
              />
            </label>
          </div>
          <p class="m-0 flex items-center gap-2 text-xs text-n-slate-11">
            <span class="i-lucide-scan-eye size-4" />
            {{
              model?.vision
                ? t('MARCOX_AI.EDITOR.MODEL_MEDIA')
                : t('MARCOX_AI.EDITOR.MODEL_TEXT')
            }}
          </p>
          <label
            v-if="model?.reasoning"
            class="block text-sm font-medium text-n-slate-12"
          >
            {{ t('MARCOX_AI.EDITOR.REASONING') }}
            <select
              v-model="form.config.reasoning_effort"
              class="!mb-0 mt-2 !h-10 w-full rounded-lg border border-n-weak bg-n-background px-3 text-sm"
            >
              <option value="low">{{ t('MARCOX_AI.EDITOR.LOW') }}</option>
              <option value="medium">{{ t('MARCOX_AI.EDITOR.MEDIUM') }}</option>
              <option value="high">{{ t('MARCOX_AI.EDITOR.HIGH') }}</option>
            </select>
          </label>
          <label v-else class="block text-sm font-medium text-n-slate-12">
            {{ t('MARCOX_AI.EDITOR.TEMPERATURE') }}
            <input
              v-model.number="form.config.temperature"
              type="number"
              min="0"
              max="2"
              step="0.1"
              class="!mb-0 mt-2 !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
            />
          </label>
          <div class="rounded-xl border border-n-weak bg-n-alpha-1 px-4">
            <AiToggleRow
              v-model="form.config.auto_response_enabled"
              :label="t('MARCOX_AI.EDITOR.ENABLE')"
              :description="t('MARCOX_AI.EDITOR.ENABLE_HINT')"
              :disabled="!connectionReady"
            />
            <p v-if="!connectionReady" class="pb-3 text-xs text-n-amber-11">
              {{ t('MARCOX_AI.EDITOR.CONNECTION_REQUIRED') }}
            </p>
          </div>
        </div>
        <div v-show="section === 'prompt'" class="space-y-4">
          <div>
            <label
              for="ai-system-prompt"
              class="text-sm font-semibold text-n-slate-12"
              >{{ t('MARCOX_AI.EDITOR.PROMPT_LABEL') }}</label
            >
            <p class="mb-3 mt-1 text-xs leading-5 text-n-slate-11">
              {{ t('MARCOX_AI.EDITOR.PROMPT_HINT') }}
            </p>
            <textarea
              id="ai-system-prompt"
              v-model="form.instructions"
              :placeholder="t('MARCOX_AI.EDITOR.PROMPT_PLACEHOLDER')"
              class="!mb-0 min-h-[22rem] w-full resize-y rounded-xl border border-n-weak bg-n-background p-4 text-sm leading-6 text-n-slate-12"
            />
          </div>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <Button
              variant="link"
              size="sm"
              :label="t('MARCOX_AI.EDITOR.PROMPT_STARTER')"
              icon="i-lucide-sparkles"
              @click="form.instructions = defaultPrompt"
            />
            <span class="text-xs text-n-slate-10">{{
              t('MARCOX_AI.EDITOR.PROMPT_COUNT', {
                count: form.instructions.length,
              })
            }}</span>
          </div>
        </div>
        <div v-show="section === 'inboxes'" class="space-y-4">
          <p class="m-0 text-sm leading-6 text-n-slate-11">
            {{ t('MARCOX_AI.EDITOR.INBOX_HINT') }}
          </p>
          <div class="flex flex-wrap items-center gap-3">
            <input
              v-model="inboxSearch"
              :placeholder="t('MARCOX_AI.EDITOR.INBOXES')"
              :aria-label="t('MARCOX_AI.EDITOR.INBOXES')"
              class="!mb-0 !h-10 min-w-40 flex-1 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
            />
            <Button
              variant="link"
              size="sm"
              :label="t('MARCOX_AI.ALL_INBOXES')"
              @click="selectAll"
            />
          </div>
          <div class="space-y-2">
            <button
              v-for="inbox in visibleInboxes"
              :key="inbox.id"
              type="button"
              role="checkbox"
              :aria-checked="form.inbox_ids.includes(inbox.id)"
              :disabled="!!ownerFor(inbox)"
              class="flex w-full items-center gap-3 rounded-xl border p-4 text-left disabled:opacity-50"
              :class="
                form.inbox_ids.includes(inbox.id)
                  ? 'border-n-blue-7 bg-n-blue-2'
                  : 'border-n-weak hover:bg-n-alpha-1'
              "
              @click="toggleInbox(inbox)"
            >
              <span
                class="flex size-5 shrink-0 items-center justify-center rounded border"
                :class="
                  form.inbox_ids.includes(inbox.id)
                    ? 'border-n-blue-9 bg-n-blue-9 text-white'
                    : 'border-n-slate-6'
                "
              >
                <span
                  v-if="form.inbox_ids.includes(inbox.id)"
                  class="i-lucide-check size-4"
                />
              </span>
              <span class="min-w-0 flex-1">
                <span
                  class="block truncate text-sm font-medium text-n-slate-12"
                  >{{ inbox.name }}</span
                >
                <span class="block text-xs text-n-slate-11">{{
                  channelLabel(inbox)
                }}</span>
              </span>
              <span v-if="ownerFor(inbox)" class="text-xs text-n-slate-11">{{
                t('MARCOX_AI.EDITOR.INBOX_OTHER', {
                  name: ownerFor(inbox).name,
                })
              }}</span>
            </button>
            <p
              v-if="!visibleInboxes.length"
              class="py-8 text-center text-sm text-n-slate-11"
            >
              {{ t('MARCOX_AI.EDITOR.INBOX_EMPTY') }}
            </p>
          </div>
        </div>
        <div v-show="section === 'behavior'" class="space-y-5">
          <AiToggleRow
            v-model="form.config.auto_start"
            :label="t('MARCOX_AI.EDITOR.AUTO_START')"
            :description="t('MARCOX_AI.EDITOR.AUTO_START_HINT')"
          />
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <label class="block text-sm font-medium text-n-slate-12">
              {{ t('MARCOX_AI.EDITOR.BUFFER') }}
              <input
                v-model.number="form.config.response_delay_seconds"
                type="number"
                min="0"
                max="300"
                class="!mb-0 mt-2 !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
              />
              <span
                class="mt-1 block text-xs font-normal leading-5 text-n-slate-11"
                >{{ t('MARCOX_AI.EDITOR.BUFFER_HINT') }}</span
              >
            </label>
            <label class="block text-sm font-medium text-n-slate-12">
              {{ t('MARCOX_AI.EDITOR.HISTORY') }}
              <input
                v-model.number="form.config.history_limit"
                type="number"
                min="10"
                max="300"
                class="!mb-0 mt-2 !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
              />
              <span
                class="mt-1 block text-xs font-normal leading-5 text-n-slate-11"
                >{{ t('MARCOX_AI.EDITOR.HISTORY_HINT') }}</span
              >
            </label>
          </div>
          <label class="block text-sm font-medium text-n-slate-12">
            {{ t('MARCOX_AI.EDITOR.HUMAN_PAUSE') }}
            <select
              v-model.number="form.config.human_pause_minutes"
              class="!mb-0 mt-2 !h-10 w-full rounded-lg border border-n-weak bg-n-background px-3 text-sm"
            >
              <option :value="0">
                {{ t('MARCOX_AI.EDITOR.PAUSE_FOREVER') }}
              </option>
              <option :value="15">{{ t('MARCOX_AI.EDITOR.PAUSE_15') }}</option>
              <option :value="60">{{ t('MARCOX_AI.EDITOR.PAUSE_60') }}</option>
              <option :value="1440">
                {{ t('MARCOX_AI.EDITOR.PAUSE_DAY') }}
              </option>
            </select>
          </label>
          <div class="rounded-xl border border-n-weak px-4">
            <AiToggleRow
              v-model="form.config.split_messages"
              :label="t('MARCOX_AI.EDITOR.SPLIT')"
              :description="t('MARCOX_AI.EDITOR.SPLIT_HINT')"
            />
            <div
              v-if="form.config.split_messages"
              class="grid grid-cols-2 gap-4 border-t border-n-weak pb-4 pt-3"
            >
              <label class="text-xs text-n-slate-11"
                >{{ t('MARCOX_AI.EDITOR.MAX_PARTS')
                }}<input
                  v-model.number="form.config.max_message_parts"
                  type="number"
                  min="1"
                  max="5"
                  class="!mb-0 mt-2 !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
              /></label>
              <label class="text-xs text-n-slate-11"
                >{{ t('MARCOX_AI.EDITOR.INTERVAL')
                }}<input
                  v-model.number="form.config.message_interval_seconds"
                  type="number"
                  min="0"
                  max="15"
                  class="!mb-0 mt-2 !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
              /></label>
            </div>
            <div class="border-t border-n-weak">
              <AiToggleRow
                v-model="form.config.allow_reactions"
                :label="t('MARCOX_AI.EDITOR.REACTIONS')"
                :description="t('MARCOX_AI.EDITOR.REACTIONS_HINT')"
              />
            </div>
          </div>
          <div
            class="divide-y divide-n-weak rounded-xl border border-n-weak px-4"
          >
            <div
              v-for="item in mediaOptions"
              :key="item.key"
              class="flex items-center gap-3"
            >
              <span
                :class="item.icon"
                class="size-5 shrink-0 text-n-slate-10"
              />
              <AiToggleRow
                v-model="form.config[item.key]"
                :label="item.label"
                :disabled="item.disabled"
                class="flex-1"
              />
            </div>
          </div>
          <AiToggleRow
            v-model="form.config.respond_to_groups"
            :label="t('MARCOX_AI.EDITOR.GROUPS')"
            :description="t('MARCOX_AI.EDITOR.GROUPS_HINT')"
          />
        </div>
      </fieldset>
    </form>
    <div
      class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak px-6 py-4"
    >
      <Button
        v-if="form.id && canEdit"
        icon="i-lucide-trash-2"
        variant="ghost"
        color="ruby"
        :aria-label="t('MARCOX_AI.DELETE')"
        @click="emit('delete', form.id)"
      />
      <span v-else />
      <div class="flex items-center gap-2">
        <Button
          :label="t('MARCOX_AI.TEST')"
          icon="i-lucide-flask-conical"
          variant="outline"
          color="slate"
          :disabled="!form.id"
          @click="emit('test', form.id)"
        />
        <Button
          v-if="canEdit"
          type="submit"
          form="marcosx-agent-editor"
          :label="t('MARCOX_AI.SAVE')"
          :is-loading="saving"
          :disabled="saving || !form.name.trim() || !form.config.model"
          icon="i-lucide-check"
        />
      </div>
    </div>
  </div>
</template>
