<script setup>
import { computed, ref } from 'vue';
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useEventListener, useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import wootConstants from 'dashboard/constants/globals';

defineProps({
  currentChat: {
    required: true,
    type: Object,
  },
});

const { uiSettings, updateUISettings } = useUISettings();
const { width: windowWidth } = useWindowSize();
const panelWidth = ref(uiSettings.value.contact_sidebar_width || 360);
const isResizing = ref(false);
let startX = 0;
let startWidth = 0;

const getClientX = event =>
  event.touches ? event.touches[0].clientX : event.clientX;

const onResizeStart = event => {
  isResizing.value = true;
  startX = getClientX(event);
  startWidth = panelWidth.value;
  document.body.style.cursor = 'col-resize';
  document.body.style.userSelect = 'none';
  event.preventDefault();
};

const onResizeMove = event => {
  if (!isResizing.value) return;
  const delta = getClientX(event) - startX;
  const direction = document.documentElement.dir === 'rtl' ? 1 : -1;
  panelWidth.value = Math.max(
    280,
    Math.min(560, startWidth + delta * direction)
  );
};

const onResizeEnd = () => {
  if (!isResizing.value) return;
  isResizing.value = false;
  document.body.style.cursor = '';
  document.body.style.userSelect = '';
  updateUISettings({ contact_sidebar_width: panelWidth.value });
};

useEventListener(document, 'mousemove', onResizeMove);
useEventListener(document, 'mouseup', onResizeEnd);
useEventListener(document, 'touchmove', onResizeMove, { passive: false });
useEventListener(document, 'touchend', onResizeEnd);

const activeTab = computed(() => {
  const { is_contact_sidebar_open: isContactSidebarOpen } = uiSettings.value;

  if (isContactSidebarOpen) {
    return 0;
  }
  return null;
});

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const closeContactPanel = () => {
  if (isSmallScreen.value && uiSettings.value?.is_contact_sidebar_open) {
    updateUISettings({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  }
};
</script>

<template>
  <div
    v-on-click-outside="[
      () => closeContactPanel(),
      {
        ignore: [
          'dialog.ProseMirror-prompt-backdrop',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="bg-n-surface-2 h-full flex flex-col fixed top-0 z-40 w-full max-w-sm md:max-w-none transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 md:relative md:flex-shrink-0 ltr:border-l rtl:border-r border-n-weak shadow-lg md:shadow-none"
    :class="[
      {
        'md:flex': activeTab === 0,
        'md:hidden': activeTab !== 0,
      },
    ]"
    :style="windowWidth < 768 ? undefined : { width: `${panelWidth}px` }"
  >
    <div
      class="hidden md:block absolute top-0 h-full w-3 cursor-col-resize z-50 ltr:-left-1.5 rtl:-right-1.5 group"
      @mousedown="onResizeStart"
      @touchstart="onResizeStart"
    >
      <div
        class="absolute top-0 h-full w-0.5 left-1/2 -translate-x-1/2 bg-transparent group-hover:bg-n-brand transition-colors"
        :class="{ 'bg-n-brand': isResizing }"
      />
    </div>
    <div class="flex flex-1 overflow-auto">
      <ContactPanel
        v-show="activeTab === 0"
        :conversation-id="currentChat.id"
        :inbox-id="currentChat.inbox_id"
      />
    </div>
  </div>
</template>
