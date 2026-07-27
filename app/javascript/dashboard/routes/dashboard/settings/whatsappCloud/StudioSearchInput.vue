<script setup>
defineProps({
  label: {
    type: String,
    required: true,
  },
  placeholder: {
    type: String,
    default: '',
  },
});

const modelValue = defineModel({
  type: String,
  default: '',
});
</script>

<template>
  <label class="relative block min-w-0 flex-1 sm:min-w-64">
    <span
      class="i-lucide-search pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-9"
      aria-hidden="true"
    />
    <span class="sr-only">{{ label }}</span>
    <input
      v-model="modelValue"
      type="search"
      class="reset-base !mb-0 h-11 w-full rounded-xl border border-n-strong bg-n-alpha-1 !pl-10 pr-3 text-sm text-n-slate-12 outline-none transition-colors placeholder:text-n-slate-9 hover:border-n-slate-7 focus:border-n-brand focus:ring-1 focus:ring-n-brand"
      :aria-label="label"
      :placeholder="placeholder"
    />
  </label>
</template>
