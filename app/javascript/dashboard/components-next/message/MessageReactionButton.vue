<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { ORIENTATION } from './constants';
import EmojiPicker from 'shared/components/emoji/EmojiPicker.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  orientation: {
    type: String,
    required: true,
  },
});

const emit = defineEmits(['react']);

const wrapper = ref(null);
const menu = ref(null);
const isOpen = ref(false);
const showMore = ref(false);
const menuPosition = ref({ top: '0px', left: '0px' });
const showPickerAbove = ref(true);
const showPickerOnRight = ref(false);

const quickEmojis = [
  '\u{1F44D}',
  '\u{2764}\u{FE0F}',
  '\u{1F602}',
  '\u{1F62E}',
  '\u{1F622}',
  '\u{1F64F}',
];
function positionMenu() {
  const rect = wrapper.value?.getBoundingClientRect();
  if (!rect) return;

  const preferredLeft =
    props.orientation === ORIENTATION.RIGHT ? rect.right - 272 : rect.left;
  const left = Math.max(8, Math.min(preferredLeft, window.innerWidth - 288));
  const top = rect.top > 48 ? rect.top - 44 : rect.bottom + 8;
  menuPosition.value = { top: `${top}px`, left: `${left}px` };
  showPickerAbove.value = top >= 264 || window.innerHeight - top < 320;
  showPickerOnRight.value = left + 352 > window.innerWidth - 8;
}

function togglePicker() {
  isOpen.value = !isOpen.value;
  showMore.value = false;
  if (isOpen.value) positionMenu();
}

function handleReaction(emoji) {
  emit('react', emoji);
  isOpen.value = false;
  showMore.value = false;
}

function handleDocumentClick(event) {
  if (
    wrapper.value?.contains(event.target) ||
    menu.value?.contains(event.target)
  )
    return;

  isOpen.value = false;
  showMore.value = false;
}

const closeOnScroll = event => {
  if (menu.value?.contains(event.target)) return;

  isOpen.value = false;
  showMore.value = false;
};

onMounted(() => {
  document.addEventListener('click', handleDocumentClick);
  window.addEventListener('scroll', closeOnScroll, true);
  window.addEventListener('resize', closeOnScroll);
});
onBeforeUnmount(() => {
  document.removeEventListener('click', handleDocumentClick);
  window.removeEventListener('scroll', closeOnScroll, true);
  window.removeEventListener('resize', closeOnScroll);
});
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
    <TeleportWithDirection v-if="isOpen" to="body">
      <div
        ref="menu"
        class="skip-context-menu fixed z-[9999] flex items-center gap-1 rounded-full border border-n-weak bg-n-background px-2 py-1 shadow-xl"
        :style="menuPosition"
        @click.stop
        @contextmenu.stop.prevent
      >
        <button
          v-for="emoji in quickEmojis"
          :key="emoji"
          type="button"
          class="flex size-8 items-center justify-center rounded-full text-lg hover:bg-n-alpha-2"
          @click="handleReaction(emoji)"
        >
          {{ emoji }}
        </button>
        <button
          type="button"
          class="flex size-8 items-center justify-center rounded-full text-n-slate-11 hover:bg-n-alpha-2"
          @click="showMore = !showMore"
        >
          <i class="i-lucide-plus size-4" />
        </button>
        <div
          v-if="showMore"
          class="absolute z-[60] w-[min(22rem,calc(100vw-1rem))]"
          :class="[
            showPickerOnRight ? 'right-0' : 'left-0',
            showPickerAbove ? 'bottom-11' : 'top-11',
          ]"
        >
          <EmojiPicker @select="handleReaction($event.value)" />
        </div>
      </div>
    </TeleportWithDirection>
  </div>
</template>
