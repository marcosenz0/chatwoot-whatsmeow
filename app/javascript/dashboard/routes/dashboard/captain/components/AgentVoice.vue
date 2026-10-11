<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import AiSelect from './AiSelect.vue';
import AiToggleRow from './AiToggleRow.vue';

const props = defineProps({
  assistantId: { type: Number, default: null },
  unsaved: { type: Boolean, default: false },
});
const settings = defineModel({ type: Object, required: true });
const { t } = useI18n();
const credentials = ref([]);
const models = ref({});
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
</script>

<template>
  <div class="space-y-5">
    <p class="text-sm text-n-slate-11">{{ t('MARCOX_AI.VOICE.HINT') }}</p>
    <AiToggleRow
      v-model="settings.enabled"
      :label="t('MARCOX_AI.VOICE.ENABLED')"
      :description="t('MARCOX_AI.VOICE.ENABLED_HINT')"
    />
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
    <div class="space-y-3 rounded-xl border border-n-weak p-4">
      <p class="m-0 text-sm font-medium">
        {{ t('MARCOX_AI.VOICE.CREDENTIAL') }}
      </p>
      <p class="text-xs text-n-slate-11">{{ t('MARCOX_AI.VOICE.KEY_HINT') }}</p>
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
          :disabled="busy || !assistantId || !encryptionReady || !key.trim()"
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
    <div class="space-y-3 rounded-xl border border-n-weak p-4">
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
          busy || unsaved || !configured || !options.voice_id || !sample.trim()
        "
        @click="preview"
      />
      <audio v-if="audioUrl" :src="audioUrl" controls class="w-full" />
    </div>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
  </div>
</template>
