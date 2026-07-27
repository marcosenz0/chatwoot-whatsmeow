<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['change']);

defineOptions({ inheritAttrs: false });

const modelValue = defineModel({
  type: [String, Number, Boolean, Array],
  default: '',
});
</script>

<template>
  <div class="relative min-w-0">
    <select
      v-model="modelValue"
      v-bind="$attrs"
      :disabled="disabled"
      class="reset-base !mb-0 !h-11 w-full !appearance-none rounded-xl border border-n-strong !bg-none bg-n-alpha-1 px-3 !pr-10 text-sm text-n-slate-12 outline-none transition-colors hover:border-n-slate-7 focus:border-n-brand focus:ring-1 focus:ring-n-brand disabled:cursor-not-allowed disabled:opacity-60"
      @change="emit('change', $event)"
    >
      <slot />
    </select>
    <Icon
      icon="i-lucide-chevron-down"
      class="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
      aria-hidden="true"
    />
  </div>
</template>
