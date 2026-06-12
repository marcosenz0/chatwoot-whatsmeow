<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { ORIENTATION } from './constants';

const props = defineProps({
  orientation: {
    type: String,
    required: true,
  },
});

const emit = defineEmits(['react']);

const wrapper = ref(null);
const isOpen = ref(false);
const showMore = ref(false);

const quickEmojis = [
  '\u{1F44D}',
  '\u{2764}\u{FE0F}',
  '\u{1F602}',
  '\u{1F62E}',
  '\u{1F622}',
  '\u{1F64F}',
];
const moreEmojis = [
  '\u{1F44F}',
  '\u{1F525}',
  '\u{1F60D}',
  '\u{1F389}',
  '\u{2705}',
  '\u{1F440}',
  '\u{1F4AF}',
  '\u{1F60E}',
  '\u{1F914}',
  '\u{1F605}',
  '\u{1F64C}',
  '\u{1F4AA}',
];

const pickerPositionClass = computed(() => {
  return props.orientation === ORIENTATION.RIGHT
    ? 'right-0 -translate-x-8'
    : 'left-0 translate-x-8';
});

function togglePicker() {
  isOpen.value = !isOpen.value;
  showMore.value = false;
}

function handleReaction(emoji) {
  emit('react', emoji);
  isOpen.value = false;
  showMore.value = false;
}

function handleDocumentClick(event) {
  if (!wrapper.value || wrapper.value.contains(event.target)) return;

  isOpen.value = false;
  showMore.value = false;
}

onMounted(() => document.addEventListener('click', handleDocumentClick));
onBeforeUnmount(() =>
  document.removeEventListener('click', handleDocumentClick)
);
</script>

<template>
  <div
    ref="wrapper"
    class="relative flex items-center opacity-0 transition-opacity group-hover/message:opacity-100 focus-within:opacity-100"
  >
    <button
      type="button"
      class="skip-context-menu flex size-7 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3"
      @click.stop="togglePicker"
      @contextmenu.stop.prevent
    >
      <i class="i-lucide-smile-plus size-4" />
    </button>
    <div
      v-if="isOpen"
      class="skip-context-menu absolute bottom-8 z-50 flex items-center gap-1 rounded-full border border-n-weak bg-n-background px-2 py-1 shadow-xl"
      :class="pickerPositionClass"
      @click.stop
      @contextmenu.stop.prevent
    >
      <button
        v-for="emoji in quickEmojis"
        :key="emoji"
        type="button"
        class="flex size-7 items-center justify-center rounded-full text-base hover:bg-n-alpha-2"
        @click="handleReaction(emoji)"
      >
        {{ emoji }}
      </button>
      <button
        type="button"
        class="flex size-7 items-center justify-center rounded-full text-n-slate-11 hover:bg-n-alpha-2"
        @click="showMore = !showMore"
      >
        <i class="i-lucide-plus size-4" />
      </button>
      <div
        v-if="showMore"
        class="absolute top-10 grid w-48 grid-cols-6 gap-1 rounded-lg border border-n-weak bg-n-background p-2 shadow-xl"
        :class="pickerPositionClass"
      >
        <button
          v-for="emoji in moreEmojis"
          :key="emoji"
          type="button"
          class="flex size-7 items-center justify-center rounded-md text-base hover:bg-n-alpha-2"
          @click="handleReaction(emoji)"
        >
          {{ emoji }}
        </button>
      </div>
    </div>
  </div>
</template>
