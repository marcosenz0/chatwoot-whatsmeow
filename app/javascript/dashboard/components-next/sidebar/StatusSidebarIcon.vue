<script setup>
defineProps({
  hasUnread: {
    type: Boolean,
    default: false,
  },
});
</script>

<template>
  <span class="relative inline-flex size-4 flex-shrink-0" aria-hidden="true">
    <svg
      viewBox="0 0 16 16"
      fill="none"
      class="size-4"
      xmlns="http://www.w3.org/2000/svg"
    >
      <circle cx="8" cy="8" r="2.75" stroke="currentColor" />
      <path
        d="M5.15 2.45A6.15 6.15 0 0 0 2.45 5.15M10.85 2.45a6.15 6.15 0 0 1 2.7 2.7M13.55 10.85a6.15 6.15 0 0 1-2.7 2.7M5.15 13.55a6.15 6.15 0 0 1-2.7-2.7"
        stroke="currentColor"
        stroke-linecap="round"
      />
    </svg>
    <span
      v-if="hasUnread"
      data-test-id="status-new-indicator"
      class="absolute -end-0.5 -top-0.5 size-2 rounded-full bg-n-teal-9 ring-2 ring-n-background"
    />
  </span>
</template>
