<script setup>
defineProps({
  title: { type: String, required: true },
  icon: { type: String, required: true },
  hint: { type: String, default: '' },
  expanded: { type: Boolean, default: false },
  accent: { type: Boolean, default: false },
});
</script>

<template>
  <details
    class="group rounded-xl border bg-n-alpha-1"
    :class="accent ? 'border-n-blue-9' : 'border-n-weak'"
    :open="expanded"
  >
    <summary
      class="flex cursor-pointer list-none flex-wrap items-center gap-3 rounded-xl px-4 py-3.5 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 [&::-webkit-details-marker]:hidden"
    >
      <span :class="icon" class="size-5 shrink-0" />
      <span class="min-w-0 flex-1"
        ><span class="block text-sm font-semibold">{{ title }}</span
        ><span v-if="hint" class="mt-0.5 block text-xs text-n-slate-11">{{
          hint
        }}</span></span
      >
      <span v-if="$slots.trailing" @click.stop><slot name="trailing" /></span>
      <span
        class="i-lucide-chevron-down size-4 shrink-0 text-n-slate-11 transition-transform group-open:rotate-180"
      />
    </summary>
    <div class="px-4 pb-4"><slot /></div>
  </details>
</template>
