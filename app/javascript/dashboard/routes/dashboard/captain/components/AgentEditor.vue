<script setup>
import { computed, ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AiToggleRow from './AiToggleRow.vue';
import AiModelSelect from './AiModelSelect.vue';
import AiSelect from './AiSelect.vue';
import AgentConnection from './AgentConnection.vue';
import AgentVision from './AgentVision.vue';
import AiPlayground from './AiPlayground.vue';
import AgentAttendance from './AgentAttendance.vue';
import AgentActivity from './AgentActivity.vue';
import AgentPromptCache from './AgentPromptCache.vue';
import AgentNotifications from './AgentNotifications.vue';
import AgentAlertList from './AgentAlertList.vue';
import AgentMemories from './AgentMemories.vue';
import AgentVoice from './AgentVoice.vue';
import AgentResources from './AgentResources.vue';
import AgentPixKeys from './AgentPixKeys.vue';
import AgentSection from './AgentSection.vue';
import { transcriptionDefaults, voiceDefaults } from './agentVoiceDefaults';

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
  error: { type: String, default: '' },
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
  'back',
]);
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const form = ref({});
const connectionDrafts = ref({});
const connectionChange = (provider, draft) => {
  connectionDrafts.value[provider] = draft;
};
const submit = () =>
  emit(
    'save',
    form.value,
    Object.entries(connectionDrafts.value)
      .filter(([, draft]) => draft.dirty)
      .map(([provider, draft]) => ({ ...draft, provider }))
  );
const initialForm = ref('');
const effectivePrompt = ref(null);
const directiveText = field =>
  computed({
    get: () => (form.value[field] || []).join('\n'),
    set: text => {
      form.value[field] = text.split('\n').filter(line => line.trim());
    },
  });
const guidelinesText = directiveText('response_guidelines');
const guardrailsText = directiveText('guardrails');
watch(
  () => [route.query.focus, form.value.id, props.initialSection],
  async () => {
    await nextTick();
    const fields = {
      system: 'ai-system-prompt',
      editorial: 'ai-editorial-prompt',
      guidelines: 'ai-guidelines',
      guardrails: 'ai-guardrails',
    };
    if (props.initialSection === 'prompt' && fields[route.query.focus]) {
      const field = document.getElementById(fields[route.query.focus]);
      field?.scrollIntoView({ block: 'center' });
      field?.focus({ preventScroll: true });
      const excerpt = window.history.state?.marcosxAiExcerpt;
      const index = excerpt ? field?.value.indexOf(excerpt) : -1;
      if (index >= 0) {
        field.setSelectionRange(index, index + excerpt.length);
        field.scrollTop = field.scrollHeight * (index / field.value.length);
      }
    }
  },
  { immediate: true }
);

const alertsDialog = ref(null);
const showPrompt = async () => {
  try {
    const { data } = await MarcosxAiAPI.getEffectivePrompt(form.value.id);
    effectivePrompt.value = data;
  } catch (error) {
    useAlert(error.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR'));
  }
};
const supportsCalls = computed(() =>
  props.inboxes.some(
    inbox =>
      form.value.inbox_ids.includes(inbox.id) &&
      inbox.channel_type === 'Channel::Whatsmeow'
  )
);
const timezoneOptions = computed(() => [
  { value: '', label: t('MARCOX_AI.EDITOR.TIMEZONE_INBOX') },
  ...[
    ...new Set([
      form.value.config.timezone,
      'UTC',
      ...Intl.supportedValuesOf('timeZone'),
    ]),
  ]
    .filter(Boolean)
    .map(value => ({ value, label: value })),
]);
const hasUnsavedChanges = computed(
  () => JSON.stringify(form.value) !== initialForm.value
);
const section = ref(props.initialSection);
const validationError = ref('');
const showInvalidField = async event => {
  event.preventDefault();
  const field = event.target;
  section.value =
    field.closest('[data-agent-section]')?.dataset.agentSection ||
    section.value;
  validationError.value = field.validationMessage;
  await nextTick();
  field.focus();
  field.scrollIntoView?.({ block: 'center' });
};
const inboxSearch = ref('');
const sections = computed(() => [
  {
    id: 'identity',
    icon: 'i-lucide-bot',
    label: t('MARCOX_AI.EDITOR.IDENTITY'),
  },
  ...(props.canEdit
    ? [
        {
          id: 'voice',
          icon: 'i-lucide-audio-lines',
          label: t('MARCOX_AI.VOICE.TITLE'),
        },
      ]
    : []),
  {
    id: 'prompt',
    icon: 'i-lucide-notebook-pen',
    label: t('MARCOX_AI.EDITOR.PROMPT'),
  },
  ...(props.canEdit
    ? [
        {
          id: 'resources',
          icon: 'i-lucide-folder-open',
          label: t('MARCOX_AI.RESOURCES.TITLE'),
        },
        {
          id: 'pix',
          icon: 'i-lucide-key-round',
          label: t('MARCOX_AI.PIX.TITLE'),
        },
      ]
    : []),
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
          id: 'notifications',
          icon: 'i-lucide-bell',
          label: t('MARCOX_AI.AUTOMATION.NOTIFICATIONS'),
        },
        {
          id: 'memories',
          icon: 'i-lucide-brain',
          label: t('MARCOX_AI.WORKSPACE.MEMORIES'),
        },
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
watch(section, value => {
  if (form.value.id)
    router.replace({
      query: { ...route.query, agent: form.value.id, section: value },
    });
});
watch(
  () => props.initialSection,
  value => {
    section.value = sections.value.some(item => item.id === value)
      ? value
      : 'identity';
  }
);
watch(
  () => props.agent,
  (agent, previous) => {
    form.value = JSON.parse(JSON.stringify(agent));
    form.value.config = {
      memory_mode: 'legacy',
      emoji_usage: 'occasional',
      message_target_characters: 160,
      separate_greeting: true,
      editorial_instructions: agent.editorial_instructions || '',
      reply_to_missed_calls: false,
      missed_call_instructions: '',
      notifications: { user_ids: [], whatsapp_numbers: [], inbox_id: null },
      alert_rules: [],
      resume_mode: 'manual',
      resume_after_minutes: 60,
      pause_on_handoff: false,
      pause_acknowledgement: true,
      ...form.value.config,
    };
    form.value.config.editorial_instructions ??=
      agent.editorial_instructions || '';
    form.value.config.prompt_cache = {
      enabled: true,
      ttl: '30m',
      ...form.value.config.prompt_cache,
    };
    form.value.config.vision = {
      provider: 'agent',
      model: '',
      max_dimension: 1600,
      video_frames: 3,
      video_interval_seconds: 5,
      instructions: '',
      ...form.value.config.vision,
    };
    connectionDrafts.value = {};
    const savedVoice = form.value.config.voice || {};
    form.value.config.transcription = {
      ...transcriptionDefaults,
      ...form.value.config.transcription,
    };
    form.value.config.voice = {
      ...voiceDefaults,
      ...savedVoice,
      minimax: { ...voiceDefaults.minimax, ...savedVoice.minimax },
      elevenlabs: { ...voiceDefaults.elevenlabs, ...savedVoice.elevenlabs },
    };
    initialForm.value = JSON.stringify(form.value);
    effectivePrompt.value = null;
    if (agent.id !== previous?.id)
      section.value =
        agent.id &&
        sections.value.some(item => item.id === props.initialSection)
          ? props.initialSection
          : 'identity';
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
const visionModel = computed(() =>
  form.value.config.vision.provider === 'agent'
    ? model.value
    : props.catalogs[form.value.config.vision.provider]?.models?.find(
        item => item.id === form.value.config.vision.model
      )
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
    disabled: visionModel.value?.vision === false,
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
    disabled: visionModel.value?.vision === false,
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
      <div class="min-w-0">
        <div class="flex items-center gap-2 text-xs text-n-slate-11">
          <Button
            type="button"
            variant="link"
            color="slate"
            icon="i-lucide-arrow-left"
            :label="t('MARCOX_AI.TABS.AGENTS')"
            @click="emit('back')"
          />
          <span>/</span
          ><span class="truncate">{{
            form.name || t('MARCOX_AI.EDITOR.NEW')
          }}</span>
          <span>/</span
          ><span>{{ sections.find(item => item.id === section)?.label }}</span>
        </div>
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
    <div class="flex min-h-0 min-w-0 flex-1 flex-col lg:flex-row">
      <aside
        class="shrink-0 border-b border-n-weak bg-n-solid-1 lg:w-52 lg:border-b-0 lg:border-e"
      >
        <nav
          class="flex h-full gap-1 overflow-x-auto px-4 py-2 lg:flex-col lg:overflow-y-auto lg:overflow-x-hidden lg:p-3"
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
              ([
                'attendance',
                'activity',
                'memories',
                'resources',
                'pix',
              ].includes(item.id) &&
                !form.id)
            "
            class="flex shrink-0 items-center gap-2 whitespace-nowrap rounded-lg px-3 py-2.5 text-start text-sm font-medium disabled:opacity-40 lg:w-full"
            :class="
              section === item.id
                ? 'bg-n-alpha-2 text-n-slate-12'
                : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12'
            "
            @click="section = item.id"
          >
            <span :class="item.icon" class="size-4 shrink-0" />
            <span
              class="min-w-0 truncate lg:overflow-visible lg:whitespace-normal"
              >{{ item.label }}</span
            >
          </button>
        </nav>
      </aside>
      <div class="flex min-h-0 min-w-0 flex-1 flex-col">
        <form
          v-show="
            ![
              'test',
              'attendance',
              'activity',
              'memories',
              'resources',
              'pix',
            ].includes(section)
          "
          id="marcosx-agent-editor"
          class="min-h-0 min-w-0 flex-1 overflow-y-auto px-4 py-6 sm:px-6"
          @submit.prevent="submit"
          @invalid.capture="showInvalidField"
        >
          <div class="mx-auto w-full max-w-6xl">
            <p
              v-if="validationError"
              role="alert"
              class="mb-4 text-sm text-n-ruby-11"
            >
              {{ validationError }}
            </p>
            <p
              v-if="error"
              role="alert"
              class="mb-4 rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
            >
              {{ error }}
            </p>
            <div class="mb-6">
              <h3 class="m-0 text-lg font-semibold text-n-slate-12">
                {{ sections.find(item => item.id === section)?.label }}
              </h3>
              <p class="m-0 mt-2 text-sm leading-6 text-n-slate-11">
                {{
                  t(`MARCOX_AI.EDITOR.SECTION_HINTS.${section.toUpperCase()}`)
                }}
              </p>
            </div>
            <fieldset :disabled="!canEdit" class="m-0 min-w-0 border-0 p-0">
              <div
                v-show="section === 'identity'"
                data-agent-section="identity"
                class="grid items-start gap-5 xl:grid-cols-2"
              >
                <AgentSection
                  :title="t('MARCOX_AI.DESIGN.AGENT_IDENTITY')"
                  icon="i-lucide-user-round"
                >
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
                      :placeholder="
                        t('MARCOX_AI.EDITOR.DESCRIPTION_PLACEHOLDER')
                      "
                      class="!mb-0 mt-2 !block !w-full !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
                    />
                  </label>
                </AgentSection>
                <AgentSection
                  :title="t('MARCOX_AI.DESIGN.MODEL_CONNECTION')"
                  icon="i-lucide-sparkles"
                >
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
                  <p
                    class="m-0 flex items-center gap-2 text-xs text-n-slate-11"
                  >
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
                    @change="connectionChange(form.config.provider, $event)"
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
                  <label
                    v-else
                    class="block text-sm font-medium text-n-slate-12"
                  >
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
                  <div
                    class="rounded-xl border border-n-weak bg-n-alpha-1 px-4"
                  >
                    <AiToggleRow
                      v-model="form.config.auto_response_enabled"
                      :label="t('MARCOX_AI.EDITOR.ENABLE')"
                      :description="t('MARCOX_AI.EDITOR.ENABLE_HINT')"
                      :disabled="!connectionReady"
                    />
                    <p
                      v-if="!connectionReady"
                      class="pb-3 text-xs text-n-amber-11"
                    >
                      {{ t('MARCOX_AI.EDITOR.CONNECTION_REQUIRED') }}
                    </p>
                  </div>
                </AgentSection>
                <div class="xl:col-span-2">
                  <AgentVision
                    v-model="form.config.vision"
                    v-model:images="form.config.process_images"
                    v-model:video="form.config.process_video"
                    :agent-provider="form.config.provider"
                    :agent-model="form.config.model"
                    :catalogs="catalogs"
                    :credentials="credentials"
                    :providers="providers"
                    :can-edit="canEdit"
                    :busy-provider="busyProvider"
                    @save-connection="
                      (provider, connection) =>
                        emit('saveConnection', provider, connection)
                    "
                    @test-connection="emit('testConnection', $event)"
                    @refresh-models="emit('refreshModels', $event)"
                    @connection-change="connectionChange"
                  />
                </div>
              </div>
              <div v-show="section === 'prompt'" class="space-y-4">
                <label class="block text-sm font-semibold">
                  {{ t('MARCOX_AI.AUTOMATION.EDITORIAL') }}
                  <textarea
                    id="ai-editorial-prompt"
                    v-model="form.config.editorial_instructions"
                    rows="8"
                    class="reset-base mt-2 w-full rounded-xl border border-n-weak bg-n-background p-4 text-sm leading-6"
                  />
                </label>
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
                <div class="grid gap-4 xl:grid-cols-2">
                  <label class="block text-sm font-semibold">
                    {{ t('MARCOX_AI.DECISION.SOURCES.GUIDELINES') }}
                    <textarea
                      id="ai-guidelines"
                      v-model="guidelinesText"
                      rows="4"
                      class="reset-base mt-2 w-full rounded-xl border border-n-weak bg-n-background p-4 text-sm leading-6"
                    />
                  </label>
                  <label class="block text-sm font-semibold">
                    {{ t('MARCOX_AI.DECISION.SOURCES.GUARDRAILS') }}
                    <textarea
                      id="ai-guardrails"
                      v-model="guardrailsText"
                      rows="4"
                      class="reset-base mt-2 w-full rounded-xl border border-n-weak bg-n-background p-4 text-sm leading-6"
                    />
                  </label>
                </div>
                <Button
                  v-if="form.id"
                  type="button"
                  size="sm"
                  variant="outline"
                  :label="t('MARCOX_AI.AUTOMATION.EFFECTIVE_PROMPT')"
                  @click="showPrompt"
                />
                <div
                  v-if="effectivePrompt"
                  class="space-y-3 rounded-xl border border-n-weak p-4"
                >
                  <p class="text-xs text-n-slate-11">
                    {{ t('MARCOX_AI.AUTOMATION.PROMPT_SAVED_HINT') }}
                  </p>
                  <details
                    v-for="kind in ['editable', 'technical']"
                    :key="kind"
                  >
                    <summary class="cursor-pointer text-sm font-semibold">
                      {{
                        t(`MARCOX_AI.AUTOMATION.PROMPT_${kind.toUpperCase()}`)
                      }}
                    </summary>
                    <pre
                      class="mt-2 whitespace-pre-wrap break-words text-xs text-n-slate-11"
                      >{{ effectivePrompt[kind] }}</pre
                    >
                  </details>
                </div>
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <Button
                    type="button"
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
                    type="button"
                    variant="link"
                    size="sm"
                    :label="t('MARCOX_AI.ALL_INBOXES')"
                    @click="selectAll"
                  />
                </div>
                <div class="grid gap-3 xl:grid-cols-2">
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
                    <span
                      v-if="ownerFor(inbox)"
                      class="text-xs text-n-slate-11"
                      >{{
                        t('MARCOX_AI.EDITOR.INBOX_OTHER', {
                          name: ownerFor(inbox).name,
                        })
                      }}</span
                    >
                  </button>
                  <p
                    v-if="!visibleInboxes.length"
                    class="py-8 text-center text-sm text-n-slate-11"
                  >
                    {{ t('MARCOX_AI.EDITOR.INBOX_EMPTY') }}
                  </p>
                </div>
              </div>
              <div
                v-show="section === 'behavior'"
                data-agent-section="behavior"
                class="grid items-start gap-5 xl:grid-cols-2"
              >
                <div class="min-w-0 space-y-5">
                  <AgentSection
                    :title="t('MARCOX_AI.DESIGN.CONTEXT_SUPPORT')"
                    icon="i-lucide-brain"
                  >
                    <label class="block text-sm font-medium">
                      {{ t('MARCOX_AI.AUTOMATION.MEMORY_MODE') }}
                      <AiSelect
                        v-model="form.config.memory_mode"
                        class="mt-2"
                        :options="
                          ['legacy', 'summary_recent', 'selected_only'].map(
                            value => ({
                              value,
                              label: t(
                                `MARCOX_AI.AUTOMATION.MEMORY_${value.toUpperCase()}`
                              ),
                            })
                          )
                        "
                        :label="t('MARCOX_AI.AUTOMATION.MEMORY_MODE')"
                      />
                    </label>
                    <AgentPromptCache
                      v-model="form.config.prompt_cache"
                      :provider="form.config.provider"
                      :model="form.config.model"
                      :api-base="credential?.api_base || ''"
                      :disabled="!canEdit"
                    />
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
                      {{ t('MARCOX_AI.EDITOR.TIMEZONE') }}
                      <AiSelect
                        :model-value="form.config.timezone || ''"
                        :options="timezoneOptions"
                        :label="t('MARCOX_AI.EDITOR.TIMEZONE')"
                        :disabled="!canEdit"
                        class="mt-2"
                        @update:model-value="form.config.timezone = $event"
                      />
                      <span
                        class="mt-1 block text-xs font-normal leading-5 text-n-slate-11"
                        >{{ t('MARCOX_AI.EDITOR.TIMEZONE_HINT') }}</span
                      >
                    </label>
                    <label class="block text-sm font-medium text-n-slate-12">
                      {{ t('MARCOX_AI.EDITOR.HUMAN_PAUSE') }}
                      <AiSelect
                        v-model="form.config.human_pause_minutes"
                        :options="[
                          {
                            value: 0,
                            label: t('MARCOX_AI.EDITOR.PAUSE_NONE'),
                          },
                          { value: 15, label: t('MARCOX_AI.EDITOR.PAUSE_15') },
                          { value: 60, label: t('MARCOX_AI.EDITOR.PAUSE_60') },
                          {
                            value: 1440,
                            label: t('MARCOX_AI.EDITOR.PAUSE_DAY'),
                          },
                        ]"
                        :label="t('MARCOX_AI.EDITOR.HUMAN_PAUSE')"
                        :disabled="!canEdit"
                        class="mt-2"
                      />
                    </label> </AgentSection
                  ><AgentSection
                    :title="t('MARCOX_AI.DESIGN.MEDIA_CHANNELS')"
                    icon="i-lucide-image"
                  >
                    <div class="divide-y divide-n-weak">
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
                  </AgentSection>
                </div>
                <div class="min-w-0 space-y-5">
                  <AgentSection
                    :title="t('MARCOX_AI.DESIGN.MESSAGE_STYLE')"
                    icon="i-lucide-messages-square"
                  >
                    <div class="divide-y divide-n-weak">
                      <AiToggleRow
                        v-model="form.config.show_typing"
                        :label="t('MARCOX_AI.EDITOR.SHOW_TYPING')"
                        :description="t('MARCOX_AI.EDITOR.SHOW_TYPING_HINT')"
                      />
                      <AiToggleRow
                        v-model="form.config.show_recording"
                        :label="t('MARCOX_AI.EDITOR.SHOW_RECORDING')"
                        :description="t('MARCOX_AI.EDITOR.SHOW_RECORDING_HINT')"
                      />
                    </div>
                    <div class="space-y-2">
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
                            v-model.number="
                              form.config.message_interval_seconds
                            "
                            type="number"
                            min="0"
                            max="15"
                            class="!mb-0 mt-2 !block !w-full !h-10 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
                        /></label>
                      </div>
                      <div
                        v-if="form.config.split_messages"
                        class="space-y-3 border-t border-n-weak py-3"
                      >
                        <label class="block text-sm font-medium">
                          {{ t('MARCOX_AI.SPLITTING.TARGET') }}
                          <input
                            v-model.number="
                              form.config.message_target_characters
                            "
                            type="number"
                            min="40"
                            max="1500"
                            class="reset-base mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
                          />
                          <span
                            class="mt-1 block text-xs font-normal text-n-slate-11"
                            >{{ t('MARCOX_AI.SPLITTING.HINT') }}</span
                          >
                        </label>
                        <AiToggleRow
                          v-model="form.config.separate_greeting"
                          :label="t('MARCOX_AI.SPLITTING.GREETING')"
                          :description="t('MARCOX_AI.SPLITTING.GREETING_HINT')"
                        />
                      </div>
                      <div class="border-t border-n-weak py-3">
                        <label class="block text-sm font-medium">
                          {{ t('MARCOX_AI.SPLITTING.EMOJI') }}
                          <AiSelect
                            v-model="form.config.emoji_usage"
                            :options="
                              ['none', 'occasional', 'expressive'].map(
                                value => ({
                                  value,
                                  label: t(
                                    `MARCOX_AI.SPLITTING.EMOJI_${value.toUpperCase()}`
                                  ),
                                })
                              )
                            "
                            :label="t('MARCOX_AI.SPLITTING.EMOJI')"
                          />
                        </label>
                      </div>
                      <div class="border-t border-n-weak">
                        <AiToggleRow
                          v-model="form.config.allow_reactions"
                          :label="t('MARCOX_AI.EDITOR.REACTIONS')"
                          :description="t('MARCOX_AI.EDITOR.REACTIONS_HINT')"
                        />
                      </div>
                    </div> </AgentSection
                  ><AgentSection
                    v-if="supportsCalls"
                    :title="t('MARCOX_AI.AUTOMATION.CALLS')"
                    icon="i-lucide-phone-missed"
                  >
                    <div v-if="supportsCalls" class="space-y-3">
                      <AiToggleRow
                        v-model="form.config.reply_to_missed_calls"
                        :label="t('MARCOX_AI.AUTOMATION.CALLS')"
                        :description="t('MARCOX_AI.AUTOMATION.CALLS_HINT')"
                      />
                      <textarea
                        v-model="form.config.missed_call_instructions"
                        rows="4"
                        :aria-label="t('MARCOX_AI.AUTOMATION.CALL_PROMPT')"
                        class="reset-base w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
                      />
                    </div>
                  </AgentSection>
                </div>
              </div>
              <AgentVoice
                v-if="section === 'voice' && canEdit"
                v-model="form.config.voice"
                v-model:transcription="form.config.transcription"
                v-model:process-audio="form.config.process_audio"
                :assistant-id="form.id"
                :unsaved="hasUnsavedChanges"
              />
              <AgentNotifications
                v-if="section === 'notifications' && canEdit"
                v-model="form.config"
                :agent-id="form.id"
                @show-alerts="alertsDialog.open()"
              />
            </fieldset>
          </div>
        </form>
        <AgentPixKeys
          v-if="section === 'pix' && form.id && canEdit"
          :agent-id="form.id"
        />
        <AgentResources
          v-if="section === 'resources' && form.id && canEdit"
          :agent-id="form.id"
        />
        <AgentMemories
          v-if="section === 'memories' && form.id && canEdit"
          :agent-id="form.id"
        />
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
    <Dialog
      ref="alertsDialog"
      width="3xl"
      :title="t('MARCOX_AI.AUTOMATION.PENDING')"
      :show-confirm-button="false"
      :cancel-button-label="t('MARCOX_AI.WORKSPACE.CLOSE')"
    >
      <div class="max-h-[65vh] overflow-y-auto">
        <AgentAlertList v-if="form.id" :agent-id="form.id" />
      </div>
    </Dialog>
  </div>
</template>
