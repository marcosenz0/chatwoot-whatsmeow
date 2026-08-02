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
      <circle cx="8" cy="8" r="3.25" stroke="currentColor" stroke-width="1.3" />
      <path
        d="M7.3 2.3a5.75 5.75 0 0 0-4.5 8.1M8.7 2.3a5.75 5.75 0 0 1 4.5 8.1M12.2 11.9a5.75 5.75 0 0 1-8.4 0"
        stroke="currentColor"
        stroke-width="1.3"
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
