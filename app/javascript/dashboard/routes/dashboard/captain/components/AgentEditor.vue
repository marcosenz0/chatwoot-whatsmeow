<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import AiToggleRow from './AiToggleRow.vue';
import AiModelSelect from './AiModelSelect.vue';
import AiSelect from './AiSelect.vue';
import AgentConnection from './AgentConnection.vue';
import AiPlayground from './AiPlayground.vue';
import AgentAttendance from './AgentAttendance.vue';
import AgentActivity from './AgentActivity.vue';

const props = defineProps({
  agent: { type: Object, required: true },
  agents: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
  credentials: { type: Array, default: () => [] },
  catalogs: { type: Object, default: () => ({}) },
  providers: { type: Object, default: () => ({}) },
  busyProvider: { type: String, default: '' },
  defaultPrompt: { type: String, default: '' },
  canEdit: { type: Boolean, default: false },
  saving: { type: Boolean, default: false },
  initialSection: { type: String, default: 'identity' },
});
const emit = defineEmits([
  'save',
  'cancel',
  'delete',
  'change',
  'saveConnection',
  'testConnection',
  'refreshModels',
]);
const { t } = useI18n();
const form = ref({});
const hasUnsavedChanges = computed(
  () => JSON.stringify(form.value) !== JSON.stringify(props.agent)
);
const section = ref(props.initialSection);
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
  { id: 'test', icon: 'i-lucide-flask-conical', label: t('MARCOX_AI.TEST') },
  ...(props.canEdit
    ? [
        {
          id: 'attendance',
          icon: 'i-lucide-messages-square',
          label: t('MARCOX_AI.COVERAGE.TITLE'),
        },
        {
          id: 'activity',
          icon: 'i-lucide-activity',
          label: t('MARCOX_AI.TABS.ACTIVITY'),
        },
      ]
    : []),
]);
watch(
  () => props.agent,
  (agent, previous) => {
    form.value = JSON.parse(JSON.stringify(agent));
    if (agent.id !== previous?.id)
      section.value = agent.id ? props.initialSection : 'identity';
  },
  { immediate: true }
);
watch(
  () => props.agent.config.auto_response_enabled,
  enabled => {
    form.value.config.auto_response_enabled = enabled;
  }
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
  { value: 'openai', label: 'OpenAI', icon: 'i-lucide-sparkles' },
  { value: 'groq', label: 'Groq', icon: 'i-lucide-zap' },
  { value: 'gemini', label: 'Google Gemini', icon: 'i-lucide-sparkle' },
];
const credential = computed(() =>
  props.credentials.find(item => item.provider === form.value.config.provider)
);
const changeProvider = provider => {
  if (provider === form.value.config.provider) return;
  form.value.config.provider = provider;
  const connection = props.credentials.find(item => item.provider === provider);
  form.value.config.model =
    connection?.model || props.catalogs[provider]?.models?.[0]?.id || '';
  form.value.config.auto_response_enabled = false;
};
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
  <div class="flex h-full min-h-0 min-w-0 flex-1 flex-col bg-n-solid-1">
    <div
      class="flex shrink-0 flex-wrap items-center justify-between gap-3 border-b border-n-weak bg-n-solid-1 px-6 py-4"
    >
      <div>
        <p class="m-0 text-xs text-n-slate-11">
          {{ t('MARCOX_AI.EDITOR.TITLE') }}
        </p>
        <h2 class="m-0 mt-1 text-lg font-semibold text-n-slate-12">
          {{ form.name || t('MARCOX_AI.EDITOR.NEW') }}
        </h2>
      </div>
      <div class="flex items-center gap-3">
        <Button
          v-if="form.id && canEdit"
          icon="i-lucide-trash-2"
          variant="ghost"
          color="ruby"
          class="lg:hidden"
          :aria-label="t('MARCOX_AI.DELETE')"
          @click="emit('delete', form.id)"
        />
        <span
          v-if="hasUnsavedChanges"
          class="hidden text-xs text-n-amber-11 lg:block"
          >{{ t('MARCOX_AI.EDITOR.UNSAVED') }}</span
        >
        <Button
          v-if="canEdit && hasUnsavedChanges"
          :label="t('MARCOX_AI.CANCEL')"
          variant="ghost"
          color="slate"
          @click="emit('cancel')"
        />
        <Button
          v-if="canEdit"
          type="submit"
          form="marcosx-agent-editor"
          :label="t('MARCOX_AI.SAVE')"
          icon="i-lucide-check"
          :is-loading="saving"
          :disabled="saving || !form.name.trim() || !form.config.model"
        />
      </div>
    </div>
    <div class="flex min-h-0 flex-1 flex-col lg:flex-row">
      <aside
        class="flex shrink-0 flex-col border-b border-n-weak bg-n-solid-1 lg:w-56 lg:border-b-0 lg:border-e"
      >
        <nav
          class="flex gap-1 overflow-x-auto p-3 lg:flex-col"
          role="tablist"
          :aria-label="t('MARCOX_AI.EDITOR.TITLE')"
        >
          <button
            v-for="item in sections"
            :key="item.id"
            type="button"
            role="tab"
            :aria-selected="section === item.id"
            :disabled="
              (item.id === 'test' && (!form.id || hasUnsavedChanges)) ||
              (['attendance', 'activity'].includes(item.id) && !form.id)
            "
            class="flex shrink-0 items-center gap-2 whitespace-nowrap rounded-lg px-3 py-2.5 text-start text-sm font-medium disabled:opacity-40"
            :class="
              section === item.id
                ? 'bg-n-alpha-2 text-n-slate-12'
                : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12'
            "
            @click="section = item.id"
          >
            <span :class="item.icon" class="size-4 shrink-0" />{{ item.label }}
          </button>
        </nav>
        <div
          v-if="form.id && canEdit"
          class="hidden border-t border-n-weak p-3 lg:mt-auto lg:block"
        >
          <Button
            icon="i-lucide-trash-2"
            :label="t('MARCOX_AI.DELETE')"
            variant="ghost"
            color="ruby"
            size="sm"
            @click="emit('delete', form.id)"
          />
        </div>
      </aside>
      <form
        v-show="!['test', 'attendance', 'activity'].includes(section)"
        id="marcosx-agent-editor"
        class="min-h-0 min-w-0 flex-1 overflow-y-auto px-6 py-6 xl:px-10"
        @submit.prevent="emit('save', form)"
      >
        <div class="mb-6">
          <h3 class="m-0 text-lg font-semibold text-n-slate-12">
            {{ sections.find(item => item.id === section)?.label }}
          </h3>
          <p class="m-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ t(`MARCOX_AI.EDITOR.SECTION_HINTS.${section.toUpperCase()}`) }}
          </p>
        </div>
        <fieldset :disabled="!canEdit" class="m-0 min-w-0 border-0 p-0">
          <div v-show="section === 'identity'" class="space-y-5">
            <label class="block text-sm font-medium text-n-slate-12">
              {{ t('MARCOX_AI.EDITOR.NAME') }}
              <input
                v-model="form.name"
                required
                maxlength="120"
                :placeholder="t('MARCOX_AI.EDITOR.NAME_PLACEHOLDER')"
                class="!mb-0 mt-2 !block !w-full !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
              />
            </label>
            <label class="block text-sm font-medium text-n-slate-12">
              {{ t('MARCOX_AI.EDITOR.DESCRIPTION') }}
              <input
                v-model="form.description"
                :placeholder="t('MARCOX_AI.EDITOR.DESCRIPTION_PLACEHOLDER')"
                class="!mb-0 mt-2 !block !w-full !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
              />
            </label>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <label class="block text-sm font-medium text-n-slate-12">
                {{ t('MARCOX_AI.EDITOR.PROVIDER') }}
                <AiSelect
                  :model-value="form.config.provider"
                  :options="providerOptions"
                  :label="t('MARCOX_AI.EDITOR.PROVIDER')"
                  :disabled="!canEdit"
                  class="mt-2"
                  @update:model-value="changeProvider"
                />
              </label>
              <label class="block text-sm font-medium text-n-slate-12">
                {{ t('MARCOX_AI.EDITOR.MODEL') }}
                <AiModelSelect
                  v-model="form.config.model"
                  :models="modelOptions"
                  :disabled="!canEdit"
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
            <AgentConnection
              :provider="form.config.provider"
              :credential="credential"
              :defaults="providers[form.config.provider]"
              :can-edit="canEdit"
              :busy="busyProvider === form.config.provider"
              @save="
                connection =>
                  emit('saveConnection', form.config.provider, connection)
              "
              @test="emit('testConnection', form.config.provider)"
              @refresh="emit('refreshModels', form.config.provider)"
            />
            <label
              v-if="model?.reasoning"
              class="block text-sm font-medium text-n-slate-12"
            >
              {{ t('MARCOX_AI.EDITOR.REASONING') }}
              <AiSelect
                v-model="form.config.reasoning_effort"
                :options="
                  ['low', 'medium', 'high'].map(value => ({
                    value,
                    label: t(`MARCOX_AI.EDITOR.${value.toUpperCase()}`),
                  }))
                "
                :label="t('MARCOX_AI.EDITOR.REASONING')"
                :disabled="!canEdit"
                class="mt-2"
              />
            </label>
            <label v-else class="block text-sm font-medium text-n-slate-12">
              {{ t('MARCOX_AI.EDITOR.TEMPERATURE') }}
              <input
                v-model.number="form.config.temperature"
                type="number"
                min="0"
                max="2"
                step="0.1"
                class="!mb-0 mt-2 !block !w-full !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
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
                  class="!mb-0 mt-2 !block !w-full !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
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
                  class="!mb-0 mt-2 !block !w-full !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
                />
                <span
                  class="mt-1 block text-xs font-normal leading-5 text-n-slate-11"
                  >{{ t('MARCOX_AI.EDITOR.HISTORY_HINT') }}</span
                >
              </label>
            </div>
            <label class="block text-sm font-medium text-n-slate-12">
              {{ t('MARCOX_AI.EDITOR.HUMAN_PAUSE') }}
              <AiSelect
                v-model="form.config.human_pause_minutes"
                :options="[
                  { value: 0, label: t('MARCOX_AI.EDITOR.PAUSE_FOREVER') },
                  { value: 15, label: t('MARCOX_AI.EDITOR.PAUSE_15') },
                  { value: 60, label: t('MARCOX_AI.EDITOR.PAUSE_60') },
                  { value: 1440, label: t('MARCOX_AI.EDITOR.PAUSE_DAY') },
                ]"
                :label="t('MARCOX_AI.EDITOR.HUMAN_PAUSE')"
                :disabled="!canEdit"
                class="mt-2"
              />
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
                    class="!mb-0 mt-2 !block !w-full !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
                /></label>
                <label class="text-xs text-n-slate-11"
                  >{{ t('MARCOX_AI.EDITOR.INTERVAL')
                  }}<input
                    v-model.number="form.config.message_interval_seconds"
                    type="number"
                    min="0"
                    max="15"
                    class="!mb-0 mt-2 !block !w-full !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
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
      <AiPlayground
        v-if="section === 'test' && form.id"
        :agents="[agent]"
        :agent-id="form.id"
        embedded
      />
      <AgentAttendance
        v-if="section === 'attendance' && form.id && canEdit"
        :agent="agent"
        :inboxes="inboxes"
      />
      <AgentActivity
        v-if="section === 'activity' && form.id && canEdit"
        :agent-id="form.id"
      />
    </div>
  </div>
</template>
