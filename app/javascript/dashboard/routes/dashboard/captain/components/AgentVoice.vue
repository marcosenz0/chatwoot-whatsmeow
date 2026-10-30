<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import AiSelect from './AiSelect.vue';
import AgentSection from './AgentSection.vue';
import AiToggleRow from './AiToggleRow.vue';
import AgentFallback from './AgentFallback.vue';
import AgentConnectionPicker from './AgentConnectionPicker.vue';
import { invertConnections } from './connectionDefaults';

const props = defineProps({
  assistantId: { type: Number, default: null },
  unsaved: { type: Boolean, default: false },
  connections: { type: Array, default: () => [] },
  providers: { type: Object, default: () => ({}) },
  canEdit: { type: Boolean, default: false },
  busyProvider: { type: String, default: '' },
  connectionStatus: { type: Object, default: () => ({}) },
  agentConfig: { type: Object, default: () => ({}) },
});
const emit = defineEmits([
  'saveConnection',
  'testConnection',
  'refreshModels',
  'connectionChange',
  'connectionCreated',
]);
const settings = defineModel({ type: Object, required: true });
const transcription = defineModel('transcription', {
  type: Object,
  required: true,
});
const processAudio = defineModel('processAudio', {
  type: Boolean,
  default: true,
});
const { t } = useI18n();
const credentials = ref([]);
const models = ref({});
const transcriptionOptions = ref({ providers: [], models: {} });
const encryptionReady = ref(false);
const key = ref('');
const busy = ref(false);
const error = ref('');
const sample = ref('');
const audioUrl = ref('');
const options = computed(() => settings.value[settings.value.provider]);
const configured = computed(() =>
  credentials.value.some(
    item => item.provider === settings.value.provider && item.configured
  )
);
const clearAudio = () => {
  if (audioUrl.value) URL.revokeObjectURL(audioUrl.value);
  audioUrl.value = '';
};
onBeforeUnmount(clearAudio);
const load = async () => {
  if (!props.assistantId) return;
  const id = props.assistantId;
  try {
    const { data } = await MarcosxAiAPI.getVoice(id);
    if (id !== props.assistantId) return;
    credentials.value = data.credentials;
    models.value = data.models;
    transcriptionOptions.value = data.transcription || {
      providers: [],
      models: {},
    };
    encryptionReady.value = data.encryption_ready;
  } catch {
    error.value = t('MARCOX_AI.VOICE.ERROR');
  }
};
watch(() => props.assistantId, load, { immediate: true });
watch(
  () => settings.value.provider,
  () => {
    key.value = '';
    error.value = '';
    clearAudio();
  }
);
const saveKey = async () => {
  busy.value = true;
  error.value = '';
  try {
    await MarcosxAiAPI.saveVoiceKey(
      props.assistantId,
      settings.value.provider,
      key.value
    );
    key.value = '';
    await load();
  } catch {
    error.value = t('MARCOX_AI.VOICE.ERROR');
  } finally {
    busy.value = false;
  }
};
const removeKey = async () => {
  busy.value = true;
  try {
    await MarcosxAiAPI.deleteVoiceKey(
      props.assistantId,
      settings.value.provider
    );
    clearAudio();
    await load();
  } catch {
    error.value = t('MARCOX_AI.VOICE.ERROR');
  } finally {
    busy.value = false;
  }
};
const preview = async () => {
  busy.value = true;
  error.value = '';
  clearAudio();
  try {
    const { data } = await MarcosxAiAPI.previewVoice(
      props.assistantId,
      sample.value
    );
    audioUrl.value = URL.createObjectURL(data);
  } catch {
    error.value = t('MARCOX_AI.VOICE.ERROR');
  } finally {
    busy.value = false;
  }
};
const numericFields = computed(() =>
  settings.value.provider === 'minimax'
    ? [
        { key: 'speed', min: 0.5, max: 2, step: 0.05 },
        { key: 'volume', min: 0.1, max: 10, step: 0.1 },
        { key: 'pitch', min: -12, max: 12, step: 1 },
      ]
    : [
        { key: 'speed', min: 0.7, max: 1.2, step: 0.05 },
        { key: 'stability', min: 0, max: 1, step: 0.05 },
        { key: 'similarity_boost', min: 0, max: 1, step: 0.05 },
        { key: 'style', min: 0, max: 1, step: 0.05 },
      ]
);
const transcriptionProvider = computed(() =>
  transcriptionOptions.value.providers.find(
    item => item.provider === transcription.value.provider
  )
);
const transcriptionProviders = computed(() => [
  {
    value: 'agent',
    label: t('MARCOX_AI.TRANSCRIPTION.AGENT_PROVIDER'),
    icon: 'i-lucide-bot',
  },
  ...['groq', 'openai', 'gemini'].map(provider => ({
    value: provider,
    label: { groq: 'Groq', openai: 'OpenAI', gemini: 'Google Gemini' }[
      provider
    ],
    icon: provider === 'groq' ? 'i-lucide-zap' : 'i-lucide-sparkles',
  })),
]);
const changeTranscriptionProvider = provider => {
  if (provider === transcription.value.provider) return;
  transcription.value = {
    provider,
    connection_id: null,
    model: transcriptionOptions.value.models[provider]?.[0] || '',
    fallback: transcription.value.fallback,
  };
};
const swapTranscription = () => {
  const inherited = {
    ...props.agentConfig,
    model: {
      groq: 'whisper-large-v3-turbo',
      openai: 'gpt-4o-transcribe',
      gemini: 'gemini-2.5-flash',
    }[props.agentConfig.provider],
  };
  invertConnections(
    transcription.value,
    transcription.value.fallback,
    inherited
  );
};
</script>

<template>
  <div class="space-y-5">
    <p class="text-sm text-n-slate-11">{{ t('MARCOX_AI.VOICE.HINT') }}</p>
    <AgentSection
      :title="t('MARCOX_AI.TRANSCRIPTION.TITLE')"
      icon="i-lucide-mic"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('MARCOX_AI.TRANSCRIPTION.HINT') }}
      </p>
      <AiToggleRow
        v-model="processAudio"
        :label="t('MARCOX_AI.TRANSCRIPTION.ENABLED')"
        :description="t('MARCOX_AI.TRANSCRIPTION.ENABLED_HINT')"
      />
      <div class="grid gap-4 sm:grid-cols-2">
        <label class="text-sm font-medium">
          {{ t('MARCOX_AI.TRANSCRIPTION.PROVIDER') }}
          <AiSelect
            :model-value="transcription.provider"
            :options="transcriptionProviders"
            :label="t('MARCOX_AI.TRANSCRIPTION.PROVIDER')"
            :disabled="!assistantId"
            @update:model-value="changeTranscriptionProvider"
          />
        </label>
        <label
          v-if="transcription.provider !== 'agent'"
          class="text-sm font-medium"
        >
          {{ t('MARCOX_AI.TRANSCRIPTION.MODEL') }}
          <AiSelect
            v-model="transcription.model"
            :options="
              (transcriptionOptions.models[transcription.provider] || []).map(
                value => ({ value, label: value })
              )
            "
            :label="t('MARCOX_AI.TRANSCRIPTION.MODEL')"
          />
        </label>
      </div>
      <p
        v-if="transcription.provider !== 'agent'"
        class="text-xs"
        :class="
          transcriptionProvider?.configured
            ? 'text-n-teal-11'
            : 'text-n-amber-11'
        "
      >
        {{
          t(
            !transcriptionProvider?.configured
              ? 'MARCOX_AI.TRANSCRIPTION.MISSING'
              : transcriptionProvider.source === 'integration'
                ? 'MARCOX_AI.TRANSCRIPTION.INTEGRATION_KEY'
                : 'MARCOX_AI.TRANSCRIPTION.AGENT_KEY'
          )
        }}
      </p>
      <p v-if="!assistantId" class="text-xs text-n-amber-11">
        {{ t('MARCOX_AI.VOICE.SAVE_FIRST') }}
      </p>
      <AgentConnectionPicker
        v-if="transcription.provider !== 'agent'"
        v-model="transcription.connection_id"
        :provider="transcription.provider"
        :credentials="connections"
        :defaults="providers[transcription.provider]"
        :disabled="!canEdit"
        @connection-created="emit('connectionCreated', $event)"
      />
      <AgentFallback
        v-if="transcription.fallback"
        v-model="transcription.fallback"
        :credentials="connections"
        :providers="providers"
        feature="transcription"
        can-swap
        :catalogs="
          Object.fromEntries(
            Object.entries(transcriptionOptions.models).map(
              ([provider, ids]) => [
                provider,
                { models: ids.map(id => ({ id, name: id })) },
              ]
            )
          )
        "
        :can-edit="canEdit"
        :busy-provider="busyProvider"
        :status="connectionStatus"
        @swap="swapTranscription"
        @save-connection="
          (provider, connection) => emit('saveConnection', provider, connection)
        "
        @test-connection="
          (provider, id, selectedModel) =>
            emit('testConnection', provider, id, selectedModel)
        "
        @refresh-models="(provider, id) => emit('refreshModels', provider, id)"
        @connection-change="
          (key, draft) => emit('connectionChange', key, draft)
        "
        @connection-created="emit('connectionCreated', $event)"
      />
    </AgentSection>
    <AiToggleRow
      v-model="settings.enabled"
      :label="t('MARCOX_AI.VOICE.ENABLED')"
      :description="t('MARCOX_AI.VOICE.ENABLED_HINT')"
    />
    <div class="grid items-start gap-5 xl:grid-cols-2">
      <div class="min-w-0 space-y-5">
        <AgentSection
          :title="t('MARCOX_AI.DESIGN.VOICE_SETTINGS')"
          icon="i-lucide-audio-lines"
        >
          <div class="grid gap-4 sm:grid-cols-2">
            <label class="text-sm font-medium">
              {{ t('MARCOX_AI.VOICE.PROVIDER') }}
              <AiSelect
                v-model="settings.provider"
                :options="[
                  { value: 'minimax', label: 'MiniMax' },
                  { value: 'elevenlabs', label: 'ElevenLabs' },
                ]"
                :label="t('MARCOX_AI.VOICE.PROVIDER')"
              />
            </label>
            <label class="text-sm font-medium">
              {{ t('MARCOX_AI.VOICE.MODE') }}
              <AiSelect
                v-model="settings.mode"
                :options="
                  ['requested', 'contextual'].map(value => ({
                    value,
                    label: t(`MARCOX_AI.VOICE.MODE_${value.toUpperCase()}`),
                  }))
                "
                :label="t('MARCOX_AI.VOICE.MODE')"
              />
            </label>
          </div>
          <div class="grid gap-4 sm:grid-cols-2">
            <label class="text-sm font-medium">
              {{ t('MARCOX_AI.VOICE.VOICE_ID') }}
              <input
                v-model="options.voice_id"
                type="text"
                class="reset-base mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
              />
              <span class="mt-1 block text-xs font-normal text-n-slate-11">{{
                t('MARCOX_AI.VOICE.ID_HINT')
              }}</span>
            </label>
            <label class="text-sm font-medium">
              {{ t('MARCOX_AI.VOICE.MODEL') }}
              <AiSelect
                v-model="options.model"
                :options="
                  (models[settings.provider] || [options.model]).map(value => ({
                    value,
                    label: value,
                  }))
                "
                :label="t('MARCOX_AI.VOICE.MODEL')"
              />
            </label>
            <label
              v-for="field in numericFields"
              :key="field.key"
              class="text-sm font-medium"
            >
              {{ t(`MARCOX_AI.VOICE.${field.key.toUpperCase()}`) }}
              <input
                v-model.number="options[field.key]"
                type="number"
                :min="field.min"
                :max="field.max"
                :step="field.step"
                class="reset-base mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
              />
            </label>
            <label class="text-sm font-medium">
              {{ t('MARCOX_AI.VOICE.MAX_CHARACTERS') }}
              <input
                v-model.number="settings.max_characters"
                type="number"
                min="100"
                max="3000"
                class="reset-base mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
              />
            </label>
          </div>
          <AiToggleRow
            v-model="settings.send_text"
            :label="t('MARCOX_AI.VOICE.SEND_TEXT')"
            :description="t('MARCOX_AI.VOICE.SEND_TEXT_HINT')"
          />
          <div
            v-if="settings.mode === 'contextual'"
            class="grid gap-4 sm:grid-cols-2"
          >
            <label class="text-sm font-medium">
              {{ t('MARCOX_AI.VOICE.MIN_TEXT_TURNS') }}
              <input
                v-model.number="settings.min_text_turns"
                type="number"
                min="1"
                max="30"
                class="reset-base mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
              />
              <span
                class="mt-2 block text-xs font-normal leading-5 text-n-slate-11"
                >{{ t('MARCOX_AI.VOICE.MIN_TEXT_TURNS_HINT') }}</span
              >
            </label>
            <label class="text-sm font-medium">
              {{ t('MARCOX_AI.VOICE.LONG_MESSAGE') }}
              <input
                v-model.number="settings.long_message_characters"
                type="number"
                min="100"
                max="2000"
                class="reset-base mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
              />
              <span
                class="mt-2 block text-xs font-normal leading-5 text-n-slate-11"
                >{{ t('MARCOX_AI.VOICE.LONG_MESSAGE_HINT') }}</span
              >
            </label>
          </div>
        </AgentSection>
        <AgentSection
          :title="t('MARCOX_AI.DESIGN.SPOKEN_TEXT')"
          icon="i-lucide-text"
        >
          <label class="block text-sm font-medium">
            {{ t('MARCOX_AI.VOICE.INSTRUCTIONS') }}
            <textarea
              v-model="settings.instructions"
              rows="4"
              class="reset-base mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
            />
          </label>
          <label class="block text-sm font-medium">
            {{ t('MARCOX_AI.VOICE.PRONUNCIATION') }}
            <textarea
              v-model="settings.pronunciation"
              rows="3"
              :placeholder="t('MARCOX_AI.VOICE.PRONUNCIATION_HINT')"
              class="reset-base mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
            />
          </label>
        </AgentSection>
      </div>
      <div class="min-w-0 space-y-5">
        <div
          class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-5"
        >
          <p class="m-0 text-sm font-medium">
            {{ t('MARCOX_AI.VOICE.CREDENTIAL') }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ t('MARCOX_AI.VOICE.KEY_HINT') }}
          </p>
          <p
            class="text-xs"
            :class="configured ? 'text-n-teal-11' : 'text-n-amber-11'"
          >
            {{
              t(
                configured
                  ? 'MARCOX_AI.VOICE.CONFIGURED'
                  : 'MARCOX_AI.VOICE.MISSING'
              )
            }}
          </p>
          <p
            v-if="!assistantId || !encryptionReady"
            class="text-xs text-n-amber-11"
          >
            {{
              t(
                !assistantId
                  ? 'MARCOX_AI.VOICE.SAVE_FIRST'
                  : 'MARCOX_AI.VOICE.ENCRYPTION'
              )
            }}
          </p>
          <input
            v-model="key"
            type="password"
            autocomplete="new-password"
            :aria-label="t('MARCOX_AI.VOICE.CREDENTIAL')"
            class="reset-base w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
          />
          <div class="flex gap-3">
            <Button
              type="button"
              :label="t('MARCOX_AI.VOICE.SAVE_KEY')"
              :disabled="
                busy || !assistantId || !encryptionReady || !key.trim()
              "
              @click="saveKey"
            />
            <Button
              v-if="configured"
              type="button"
              variant="ghost"
              color="ruby"
              :label="t('MARCOX_AI.VOICE.DELETE_KEY')"
              :disabled="busy"
              @click="removeKey"
            />
          </div>
        </div>
        <div
          class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-5"
        >
          <p class="text-sm font-medium">{{ t('MARCOX_AI.VOICE.PREVIEW') }}</p>
          <p class="text-xs text-n-slate-11">
            {{ t('MARCOX_AI.VOICE.PREVIEW_HINT') }}
          </p>
          <textarea
            v-model="sample"
            rows="3"
            :aria-label="t('MARCOX_AI.VOICE.PREVIEW')"
            class="reset-base w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
          />
          <p v-if="unsaved" class="text-xs text-n-amber-11">
            {{ t('MARCOX_AI.VOICE.SAVE_FIRST') }}
          </p>
          <Button
            type="button"
            :label="t('MARCOX_AI.VOICE.GENERATE')"
            :is-loading="busy"
            :disabled="
              busy ||
              unsaved ||
              !configured ||
              !options.voice_id ||
              !sample.trim()
            "
            @click="preview"
          />
          <audio v-if="audioUrl" :src="audioUrl" controls class="w-full" />
        </div>
      </div>
    </div>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
  </div>
</template>
