<script setup>
defineOptions({ inheritAttrs: false });
</script>

<template>
  <svg
    v-bind="$attrs"
    viewBox="0 0 24 24"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    aria-hidden="true"
  >
    <rect
      x="9"
      y="3.5"
      width="6"
      height="6"
      rx="1.75"
      fill="currentColor"
      transform="rotate(45 12 6.5)"
    />
    <rect
      x="14.5"
      y="9"
      width="6"
      height="6"
      rx="1.75"
      fill="currentColor"
      transform="rotate(45 17.5 12)"
    />
    <rect
      x="9"
      y="14.5"
      width="6"
      height="6"
      rx="1.75"
      fill="currentColor"
      transform="rotate(45 12 17.5)"
    />
    <rect
      x="3.5"
      y="9"
      width="6"
      height="6"
      rx="1.75"
      fill="currentColor"
      transform="rotate(45 6.5 12)"
    />
  </svg>
</template>
