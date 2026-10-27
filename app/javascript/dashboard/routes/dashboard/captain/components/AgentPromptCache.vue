<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AiToggleRow from './AiToggleRow.vue';
import AiSelect from './AiSelect.vue';

const props = defineProps({
  modelValue: { type: Object, required: true },
  provider: { type: String, required: true },
  model: { type: String, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const supported = computed(() => {
  const version = props.model.match(/^gpt-(\d+)(?:\.(\d+))?(?:-|$)/);
  return (
    props.provider === 'openai' &&
    version &&
    (Number(version[1]) >= 6 ||
      (Number(version[1]) === 5 && Number(version[2]) >= 6))
  );
});
const update = (field, value) =>
  emit('update:modelValue', { ...props.modelValue, [field]: value });
</script>

<template>
  <div class="min-w-0 space-y-3 rounded-xl border border-n-weak p-4">
    <AiToggleRow
      :model-value="modelValue.enabled"
      :label="t('MARCOX_AI.CACHE.TITLE')"
      :description="t('MARCOX_AI.CACHE.BODY')"
      :disabled="disabled || !supported"
      @update:model-value="update('enabled', $event)"
    />
    <p v-if="!supported" class="m-0 text-xs leading-5 text-n-slate-11">
      {{ t('MARCOX_AI.CACHE.UNSUPPORTED') }}
    </p>
    <template v-else-if="modelValue.enabled">
      <label class="block text-sm font-medium text-n-slate-12">
        {{ t('MARCOX_AI.CACHE.LIFETIME') }}
        <AiSelect
          :model-value="modelValue.ttl"
          :disabled="disabled"
          :label="t('MARCOX_AI.CACHE.LIFETIME')"
          :options="[
            { value: '30m', label: t('MARCOX_AI.CACHE.THIRTY_MINUTES') },
            { value: '12h', label: t('MARCOX_AI.CACHE.TWELVE_HOURS') },
          ]"
          class="mt-2"
          @update:model-value="update('ttl', $event)"
        />
      </label>
      <p class="m-0 text-xs leading-5 text-n-slate-11">
        {{
          t(
            `MARCOX_AI.CACHE.${modelValue.ttl === '12h' ? 'LONG_HINT' : 'SHORT_HINT'}`
          )
        }}
      </p>
    </template>
  </div>
</template>
