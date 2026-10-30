<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/marcosxAi';
import Button from 'dashboard/components-next/button/Button.vue';
import AiSelect from './AiSelect.vue';

const props = defineProps({
  provider: { type: String, required: true },
  credentials: { type: Array, default: () => [] },
  defaults: { type: Object, default: () => ({}) },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['connectionCreated']);
const selected = defineModel({ type: [Number, String], default: null });
const { t } = useI18n();
const creating = ref(false);
const name = ref('');
const key = ref('');
const busy = ref(false);
const error = ref('');
const options = computed(() => [
  {
    value: '',
    label: t('MARCOX_AI.FALLBACK.DEFAULT_CONNECTION'),
    icon: 'i-lucide-key-round',
  },
  ...props.credentials
    .filter(item => item.provider === props.provider && item.id)
    .map(item => ({
      value: String(item.id),
      label: item.name || item.display_name || item.provider,
      icon:
        item.health?.state === 'error'
          ? 'i-lucide-circle-x'
          : 'i-lucide-key-round',
    })),
]);
const save = async () => {
  if (busy.value || !name.value.trim() || !key.value.trim()) return;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.saveCredential(null, {
      credential: {
        provider: props.provider,
        name: name.value.trim(),
        api_key: key.value.trim(),
        api_base: props.defaults.default_api_base,
        model: props.defaults.default_model,
        enabled: true,
      },
    });
    key.value = '';
    creating.value = false;
    selected.value = data.credential.id;
    emit('connectionCreated', data.credential);
  } catch (e) {
    error.value = e.response?.data?.error || t('MARCOX_AI.ERROR');
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <div class="space-y-3">
    <label class="block text-sm font-medium">
      {{ t('MARCOX_AI.FALLBACK.CONNECTION') }}
      <AiSelect
        :model-value="selected ? String(selected) : ''"
        :options="options"
        :label="t('MARCOX_AI.FALLBACK.CONNECTION')"
        :disabled="disabled || busy"
        class="mt-2"
        @update:model-value="selected = $event ? Number($event) : null"
      />
    </label>
    <Button
      v-if="!disabled"
      type="button"
      size="sm"
      variant="link"
      icon="i-lucide-plus"
      :label="t('MARCOX_AI.FALLBACK.ADD_CONNECTION')"
      @click="creating = !creating"
    />
    <div v-if="creating" class="space-y-3 rounded-lg border border-n-weak p-3">
      <label class="block text-sm font-medium">
        {{ t('MARCOX_AI.FALLBACK.NAME') }}
        <input
          v-model="name"
          type="text"
          maxlength="80"
          class="reset-base !mb-0 mt-2 h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
        />
      </label>
      <label class="block text-sm font-medium">
        {{ t('MARCOX_AI.PROVIDERS.KEY') }}
        <input
          v-model="key"
          type="password"
          autocomplete="new-password"
          class="reset-base !mb-0 mt-2 h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
        />
      </label>
      <p class="m-0 text-xs text-n-slate-11">
        {{ t('MARCOX_AI.FALLBACK.NEW_HINT') }}
      </p>
      <p v-if="error" role="alert" class="m-0 text-xs text-n-ruby-11">
        {{ error }}
      </p>
      <Button
        type="button"
        size="sm"
        :label="t('MARCOX_AI.PROVIDERS.CONNECT')"
        :disabled="busy || !name.trim() || !key.trim()"
        :is-loading="busy"
        @click="save"
      />
    </div>
  </div>
</template>
