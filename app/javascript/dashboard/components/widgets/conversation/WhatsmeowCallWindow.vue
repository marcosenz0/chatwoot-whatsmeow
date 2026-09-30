<script setup>
import { computed, ref, watch } from 'vue';
import { useWindowSize } from '@vueuse/core';
import { useI18n } from 'vue-i18n';

const props = defineProps({ video: { type: Boolean, default: false } });
const { t } = useI18n();
const { width: viewportWidth, height: viewportHeight } = useWindowSize();
const width = ref(props.video ? 560 : 384);
const height = ref(props.video ? 480 : 280);
const x = ref(viewportWidth.value - width.value - 24);
const y = ref(viewportHeight.value - height.value - 24);
const expanded = ref(false);
const moving = ref(false);
let gesture;
let previousGeometry;
const bounds = computed(() => ({
  width: Math.max(280, viewportWidth.value - 16),
  height: Math.max(200, viewportHeight.value - 16),
}));

const constrain = () => {
  width.value = Math.min(Math.max(width.value, 320), bounds.value.width);
  height.value = Math.min(
    Math.max(height.value, props.video ? 360 : 240),
    bounds.value.height
  );
  x.value = Math.max(
    8,
    Math.min(x.value, viewportWidth.value - width.value - 8)
  );
  y.value = Math.max(
    8,
    Math.min(y.value, viewportHeight.value - height.value - 8)
  );
};
const startGesture = (event, resize = false) => {
  if (event.button !== 0 || expanded.value) return;
  if (!resize && event.target.closest('button, input, select')) return;
  gesture = {
    x: event.clientX,
    y: event.clientY,
    left: x.value,
    top: y.value,
    width: width.value,
    height: height.value,
    resize,
  };
  event.currentTarget.setPointerCapture(event.pointerId);
  moving.value = true;
};
const moveGesture = event => {
  if (!gesture) return;
  const dx = event.clientX - gesture.x;
  const dy = event.clientY - gesture.y;
  if (gesture.resize) {
    width.value = gesture.width + dx;
    height.value = gesture.height + dy;
  } else {
    x.value = gesture.left + dx;
    y.value = gesture.top + dy;
  }
  constrain();
};
const finishGesture = () => {
  gesture = null;
  moving.value = false;
};
const moveByKeyboard = (event, resize = false) => {
  const changes = {
    ArrowLeft: [-16, 0],
    ArrowRight: [16, 0],
    ArrowUp: [0, -16],
    ArrowDown: [0, 16],
  };
  const delta = changes[event.key];
  if (!delta || expanded.value) return;
  event.preventDefault();
  if (resize) {
    width.value += delta[0];
    height.value += delta[1];
  } else {
    x.value += delta[0];
    y.value += delta[1];
  }
  constrain();
};
const toggleExpanded = () => {
  if (expanded.value) {
    x.value = previousGeometry.x;
    y.value = previousGeometry.y;
    width.value = previousGeometry.width;
    height.value = previousGeometry.height;
  } else {
    previousGeometry = {
      x: x.value,
      y: y.value,
      width: width.value,
      height: height.value,
    };
    x.value = 8;
    y.value = 8;
    width.value = bounds.value.width;
    height.value = bounds.value.height;
  }
  expanded.value = !expanded.value;
  constrain();
};
watch([viewportWidth, viewportHeight], constrain, { immediate: true });
watch(
  () => props.video,
  video => {
    if (video && !expanded.value) {
      width.value = Math.max(width.value, 560);
      height.value = Math.max(height.value, 480);
    }
    constrain();
  }
);
</script>

<template>
  <svg
    class="pointer-events-none fixed inset-0 z-50 h-screen w-screen"
    role="presentation"
  >
    <foreignObject :x="x" :y="y" :width="width" :height="height">
      <div
        xmlns="http://www.w3.org/1999/xhtml"
        class="pointer-events-auto relative flex h-full w-full flex-col rounded-2xl border border-n-weak bg-n-solid-1 text-n-slate-12 shadow-xl"
        role="dialog"
        :aria-label="t('CONVERSATION.WHATSMEOW_CALL.TITLE')"
      >
        <div
          class="flex shrink-0 touch-none select-none items-center gap-2 border-b border-n-weak px-4 py-3"
          :class="moving ? 'cursor-grabbing' : 'cursor-grab'"
          role="button"
          tabindex="0"
          :aria-label="t('CONVERSATION.WHATSMEOW_CALL.MOVE_WINDOW')"
          @pointerdown="startGesture($event)"
          @pointermove="moveGesture"
          @pointerup="finishGesture"
          @pointercancel="finishGesture"
          @keydown="moveByKeyboard($event)"
          @dblclick="toggleExpanded"
        >
          <div class="min-w-0 flex-1"><slot name="header" /></div>
          <button
            type="button"
            class="flex size-8 shrink-0 items-center justify-center rounded-lg hover:bg-n-alpha-2 focus-visible:ring-2 focus-visible:ring-n-brand"
            :aria-label="
              t(
                `CONVERSATION.WHATSMEOW_CALL.${expanded ? 'RESTORE_WINDOW' : 'EXPAND_WINDOW'}`
              )
            "
            @click="toggleExpanded"
          >
            <span
              :class="expanded ? 'i-lucide-minimize-2' : 'i-lucide-maximize-2'"
              class="size-4"
            />
          </button>
        </div>
        <div class="flex min-h-0 flex-1 flex-col gap-2 p-3"><slot /></div>
        <div class="shrink-0 px-3 pb-5 pt-2"><slot name="footer" /></div>
        <button
          v-if="!expanded"
          type="button"
          class="absolute bottom-1 right-1 flex size-6 touch-none items-center justify-center rounded cursor-se-resize text-n-slate-10 focus-visible:ring-2 focus-visible:ring-n-brand"
          :aria-label="t('CONVERSATION.WHATSMEOW_CALL.RESIZE_WINDOW')"
          @pointerdown.stop="startGesture($event, true)"
          @pointermove="moveGesture"
          @pointerup="finishGesture"
          @pointercancel="finishGesture"
          @keydown="moveByKeyboard($event, true)"
        >
          <span class="i-lucide-grip size-4" />
        </button>
      </div>
    </foreignObject>
  </svg>
</template>
