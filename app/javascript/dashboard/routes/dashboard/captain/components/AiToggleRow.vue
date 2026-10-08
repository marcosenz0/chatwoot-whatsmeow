<script setup>
defineProps({
  modelValue: { type: Boolean, default: false },
  label: { type: String, required: true },
  description: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
</script>

<template>
  <div class="flex items-center justify-between gap-5 py-3">
    <div>
      <p class="m-0 text-sm font-medium text-n-slate-12">{{ label }}</p>
      <p v-if="description" class="m-0 mt-1 text-xs leading-5 text-n-slate-11">
        {{ description }}
      </p>
    </div>
    <button
      type="button"
      role="switch"
      :aria-checked="modelValue"
      :aria-label="label"
      :disabled="disabled"
      class="!p-0 relative inline-flex h-5 w-9 flex-shrink-0 items-center rounded-full transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 disabled:opacity-40"
      :class="modelValue ? 'bg-n-blue-9' : 'bg-n-slate-6'"
      @click="emit('update:modelValue', !modelValue)"
    >
      <span
        class="h-4 w-4 rounded-full bg-white shadow transition-transform"
        :class="modelValue ? 'translate-x-[18px]' : 'translate-x-0.5'"
      />
    </button>
  </div>
</template>
