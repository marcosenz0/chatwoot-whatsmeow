<script setup>
defineProps({
  title: { type: String, required: true },
  icon: { type: String, default: '' },
});
</script>

<template>
  <section
    class="min-w-0 space-y-4 rounded-xl border border-n-weak bg-n-solid-2 p-5"
  >
    <h4
      class="m-0 flex items-center gap-2 text-sm font-semibold text-n-slate-12"
    >
      <span v-if="icon" :class="icon" class="size-4 shrink-0 text-n-slate-11" />
      {{ title }}
    </h4>
    <slot />
  </section>
</template>
