<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  modelValue: { type: String, default: '' },
  models: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const options = computed(() => {
  if (
    !props.modelValue ||
    props.models.some(model => model.id === props.modelValue)
  )
    return props.models;
  return [{ id: props.modelValue, name: props.modelValue }, ...props.models];
});
</script>

<template>
  <select
    :value="modelValue"
    :disabled="disabled"
    :aria-label="t('MARCOX_AI.EDITOR.MODEL')"
    class="!w-full !h-10 !mb-0 rounded-lg border border-n-weak bg-n-background px-3 text-sm text-n-slate-12 disabled:opacity-50"
    @change="emit('update:modelValue', $event.target.value)"
  >
    <option v-for="model in options" :key="model.id" :value="model.id">
      {{ model.name
      }}{{
        model.recommended ? ` · ${t('MARCOX_AI.PROVIDERS.RECOMMENDED')}` : ''
      }}
    </option>
  </select>
</template>
