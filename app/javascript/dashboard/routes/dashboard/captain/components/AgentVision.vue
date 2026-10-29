<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AgentSection from './AgentSection.vue';
import AiSelect from './AiSelect.vue';
import AiModelSelect from './AiModelSelect.vue';
import AiToggleRow from './AiToggleRow.vue';
import AgentConnection from './AgentConnection.vue';
import AgentConnectionPicker from './AgentConnectionPicker.vue';
import AgentFallback from './AgentFallback.vue';
import { connectionActive } from './connectionDefaults';

const props = defineProps({
  agentProvider: { type: String, required: true },
  agentModel: { type: String, required: true },
  catalogs: { type: Object, default: () => ({}) },
  credentials: { type: Array, default: () => [] },
  providers: { type: Object, default: () => ({}) },
  canEdit: { type: Boolean, default: false },
  busyProvider: { type: String, default: '' },
  status: { type: Object, default: () => ({}) },
});
const emit = defineEmits([
  'saveConnection',
  'testConnection',
  'refreshModels',
  'connectionChange',
  'connectionCreated',
]);
const settings = defineModel({ type: Object, required: true });
const images = defineModel('images', { type: Boolean, default: true });
const video = defineModel('video', { type: Boolean, default: true });
const { t } = useI18n();
const provider = computed(() =>
  settings.value.provider === 'agent'
    ? props.agentProvider
    : settings.value.provider
);
const models = computed(() =>
  (
    (
      props.catalogs[`${provider.value}:${settings.value.connection_id}`] ||
      props.catalogs[provider.value]
    )?.models || []
  ).filter(model => model.vision)
);
const currentModel = computed(() =>
  models.value.find(
    model =>
      model.id ===
      (settings.value.provider === 'agent'
        ? props.agentModel
        : settings.value.model)
  )
);
const credential = computed(() =>
  props.credentials.find(
    item =>
      item.provider === provider.value &&
      (!settings.value.connection_id ||
        item.id === settings.value.connection_id)
  )
);
const changeProvider = value => {
  settings.value.provider = value;
  settings.value.connection_id = null;
  settings.value.model = value === 'agent' ? '' : models.value[0]?.id || '';
};
const fields = [
  { key: 'max_dimension', min: 512, max: 1600 },
  { key: 'video_frames', min: 1, max: 6 },
  { key: 'video_interval_seconds', min: 1, max: 30 },
];
</script>

<template>
  <AgentSection :title="t('MARCOX_AI.VISION.TITLE')" icon="i-lucide-scan-eye">
    <p class="m-0 text-sm leading-6 text-n-slate-11">
      {{ t('MARCOX_AI.VISION.HINT') }}
    </p>
    <AiToggleRow v-model="images" :label="t('MARCOX_AI.EDITOR.IMAGES')" />
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <label class="text-sm font-medium">
        {{ t('MARCOX_AI.EDITOR.PROVIDER') }}
        <AiSelect
          :model-value="settings.provider"
          :label="t('MARCOX_AI.VISION.PROVIDER')"
          :options="[
            {
              value: 'agent',
              label: t('MARCOX_AI.VISION.AGENT'),
              icon: 'i-lucide-bot',
            },
            { value: 'groq', label: 'Groq', icon: 'i-lucide-zap' },
            { value: 'openai', label: 'OpenAI', icon: 'i-lucide-sparkles' },
            {
              value: 'gemini',
              label: 'Google Gemini',
              icon: 'i-lucide-sparkle',
            },
          ]"
          :disabled="!canEdit"
          class="mt-2"
          @update:model-value="changeProvider"
        />
      </label>
      <label v-if="settings.provider !== 'agent'" class="text-sm font-medium">
        {{ t('MARCOX_AI.VISION.MODEL') }}
        <AiModelSelect
          v-model="settings.model"
          :label="t('MARCOX_AI.VISION.MODEL')"
          :models="models"
          :disabled="!canEdit"
          class="mt-2"
        />
      </label>
    </div>
    <p
      v-if="!currentModel?.vision"
      role="status"
      class="m-0 text-xs text-n-amber-11"
    >
      {{ t('MARCOX_AI.VISION.UNSUPPORTED') }}
    </p>
    <p v-else class="m-0 text-xs text-n-slate-11">
      {{ t('MARCOX_AI.VISION.LIMIT', { count: currentModel.max_images || 6 }) }}
    </p>
    <AgentConnection
      v-if="
        settings.provider !== 'agent' &&
        (provider !== agentProvider || settings.connection_id)
      "
      :provider="provider"
      :credential="credential"
      :defaults="providers[provider]"
      :can-edit="canEdit"
      :busy="busyProvider === provider"
      :active="connectionActive(status, credential, provider, 'primary')"
      @save="emit('saveConnection', provider, $event)"
      @test="emit('testConnection', provider, credential?.id, settings.model)"
      @refresh="emit('refreshModels', provider, settings.connection_id)"
      @change="
        emit(
          'connectionChange',
          credential?.id ? `connection:${credential.id}` : provider,
          $event
        )
      "
    />
    <p
      v-else-if="settings.provider !== 'agent'"
      class="m-0 text-xs text-n-slate-11"
    >
      {{ t('MARCOX_AI.VISION.SHARED') }}
    </p>
    <AgentConnectionPicker
      v-if="settings.provider !== 'agent'"
      v-model="settings.connection_id"
      :provider="provider"
      :credentials="credentials"
      :defaults="providers[provider]"
      :disabled="!canEdit"
      @connection-created="emit('connectionCreated', $event)"
      @update:model-value="emit('refreshModels', provider, $event)"
    />
    <AgentFallback
      v-model="settings.fallback"
      :credentials="credentials"
      :providers="providers"
      :catalogs="catalogs"
      :can-edit="canEdit"
      :busy-provider="busyProvider"
      :status="status"
      vision
      @save-connection="
        (selectedProvider, connection) =>
          emit('saveConnection', selectedProvider, connection)
      "
      @test-connection="
        (selectedProvider, id, selectedModel) =>
          emit('testConnection', selectedProvider, id, selectedModel)
      "
      @refresh-models="
        (selectedProvider, id) => emit('refreshModels', selectedProvider, id)
      "
      @connection-change="(key, draft) => emit('connectionChange', key, draft)"
      @connection-created="emit('connectionCreated', $event)"
    />
    <AiToggleRow
      v-model="video"
      :label="t('MARCOX_AI.EDITOR.VIDEO')"
      :description="t('MARCOX_AI.VISION.VIDEO_HINT')"
    />
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <label
        v-for="field in fields"
        :key="field.key"
        class="text-sm font-medium"
      >
        {{ t(`MARCOX_AI.VISION.${field.key.toUpperCase()}`) }}
        <input
          v-model.number="settings[field.key]"
          type="number"
          :min="field.min"
          :max="field.max"
          step="1"
          class="reset-base !mb-0 mt-2 h-10 w-full rounded-lg border border-n-weak bg-n-background px-3 text-sm"
        />
      </label>
    </div>
    <label class="block text-sm font-medium">
      {{ t('MARCOX_AI.VISION.INSTRUCTIONS') }}
      <textarea
        v-model="settings.instructions"
        rows="3"
        maxlength="4000"
        class="reset-base !mb-0 mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
      />
    </label>
    <p class="m-0 text-xs leading-5 text-n-slate-11">
      {{ t('MARCOX_AI.VISION.INSTRUCTIONS_HINT') }}
    </p>
  </AgentSection>
</template>
