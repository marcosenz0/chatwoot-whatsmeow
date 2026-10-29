<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AiToggleRow from './AiToggleRow.vue';
import AiSelect from './AiSelect.vue';
import AiModelSelect from './AiModelSelect.vue';
import AgentConnection from './AgentConnection.vue';
import AgentConnectionPicker from './AgentConnectionPicker.vue';
import AgentOutputLimit from './AgentOutputLimit.vue';
import { connectionActive, providerChoices } from './connectionDefaults';

const props = defineProps({
  credentials: { type: Array, default: () => [] },
  providers: { type: Object, default: () => ({}) },
  catalogs: { type: Object, default: () => ({}) },
  vision: { type: Boolean, default: false },
  canEdit: { type: Boolean, default: false },
  busyProvider: { type: String, default: '' },
  status: { type: Object, default: () => ({}) },
  feature: { type: String, default: 'chat' },
});
const emit = defineEmits([
  'saveConnection',
  'testConnection',
  'refreshModels',
  'connectionChange',
  'connectionCreated',
]);
const settings = defineModel({ type: Object, required: true });
const { t } = useI18n();
const models = computed(() =>
  (
    (
      props.catalogs[
        `${settings.value.provider}:${settings.value.connection_id}`
      ] || props.catalogs[settings.value.provider]
    )?.models || []
  ).filter(model => !props.vision || model.vision)
);
const credential = computed(() =>
  props.credentials.find(
    item =>
      item.provider === settings.value.provider &&
      (!settings.value.connection_id ||
        item.id === settings.value.connection_id)
  )
);
const changeProvider = value => {
  settings.value.provider = value;
  settings.value.connection_id = null;
  settings.value.model =
    models.value[0]?.id ||
    (props.feature === 'transcription'
      ? {
          groq: 'whisper-large-v3-turbo',
          openai: 'gpt-4o-transcribe',
          gemini: 'gemini-2.5-flash',
        }[value]
      : props.providers[value]?.default_model) ||
    '';
};
const active = computed(() =>
  connectionActive(
    props.status,
    credential.value,
    settings.value.provider,
    'fallback'
  )
);
watch(
  [() => settings.value.provider, () => settings.value.connection_id],
  ([provider, id]) => {
    if (props.feature !== 'transcription') emit('refreshModels', provider, id);
  }
);
</script>

<template>
  <section class="space-y-3 rounded-xl border border-n-weak bg-n-alpha-1 p-4">
    <AiToggleRow
      v-model="settings.enabled"
      :label="t('MARCOX_AI.FALLBACK.ENABLED')"
      :description="t('MARCOX_AI.FALLBACK.HINT')"
      :disabled="!canEdit"
    />
    <div v-if="settings.enabled" class="space-y-4">
      <p
        v-if="active"
        role="status"
        class="m-0 flex items-center gap-2 text-sm font-medium text-n-teal-11"
      >
        <span class="i-lucide-circle-check size-4 shrink-0" />{{
          t('MARCOX_AI.FALLBACK.ACTIVE')
        }}
      </p>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="text-sm font-medium">
          {{ t('MARCOX_AI.FALLBACK.PROVIDER') }}
          <AiSelect
            :model-value="settings.provider"
            :options="providerChoices"
            :label="t('MARCOX_AI.FALLBACK.PROVIDER')"
            class="mt-2"
            :disabled="!canEdit"
            @update:model-value="changeProvider"
          />
        </label>
        <label class="text-sm font-medium">
          {{ t('MARCOX_AI.FALLBACK.MODEL') }}
          <AiModelSelect
            v-model="settings.model"
            :models="models"
            :label="t('MARCOX_AI.FALLBACK.MODEL')"
            class="mt-2"
            :disabled="!canEdit"
          />
        </label>
      </div>
      <AgentOutputLimit
        v-if="feature !== 'transcription'"
        v-model="settings.max_output_tokens"
        :provider="settings.provider"
        :disabled="!canEdit"
      />
      <AgentConnectionPicker
        v-model="settings.connection_id"
        :provider="settings.provider"
        :credentials="credentials"
        :defaults="providers[settings.provider]"
        :disabled="!canEdit"
        @connection-created="emit('connectionCreated', $event)"
      />
      <AgentConnection
        :provider="settings.provider"
        :credential="credential"
        :defaults="providers[settings.provider]"
        :can-edit="canEdit"
        :busy="busyProvider === settings.provider"
        :active="active"
        @save="emit('saveConnection', settings.provider, $event)"
        @test="
          emit(
            'testConnection',
            settings.provider,
            credential?.id,
            settings.model
          )
        "
        @refresh="
          emit('refreshModels', settings.provider, settings.connection_id)
        "
        @change="
          emit(
            'connectionChange',
            credential?.id ? `connection:${credential.id}` : settings.provider,
            { ...$event, provider: settings.provider }
          )
        "
      />
    </div>
  </section>
</template>
