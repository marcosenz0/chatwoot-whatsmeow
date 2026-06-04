<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { ORIENTATION } from './constants';

const props = defineProps({
  reactions: {
    type: Array,
    default: () => [],
  },
  currentUserReaction: {
    type: Object,
    default: null,
  },
  displayLabel: {
    type: String,
    required: true,
  },
  orientation: {
    type: String,
    default: ORIENTATION.LEFT,
  },
});

const emit = defineEmits(['remove']);

const isOpen = ref(false);
const container = ref(null);

const LABELS = {
  title: 'Rea\u00e7\u00f5es',
  currentUser: 'Voc\u00ea',
  removeHint: 'Clique para remover',
  fallbackSender: 'WhatsApp',
};

const reactionEmoji = reaction => {
  if (typeof reaction === 'string') return reaction;

  return (reaction?.emoji || reaction?.reaction || '').toString();
};

const reactionSenderKey = reaction =>
  reaction?.sender ||
  reaction?.sender_id ||
  reaction?.senderId ||
  reaction?.whatsapp_id ||
  reaction?.whatsappId ||
  '';

const isCurrentUserReaction = reaction => {
  if (!reaction || typeof reaction === 'string') return false;

  if (reaction.from_me || reaction.fromMe || reaction.sender === 'chatwoot') {
    return true;
  }

  if (!props.currentUserReaction) return false;

  return (
    reactionSenderKey(reaction) === reactionSenderKey(props.currentUserReaction)
  );
};

const normalizedReactions = computed(() =>
  props.reactions
    .map(reaction => ({
      emoji: reactionEmoji(reaction),
      senderName: isCurrentUserReaction(reaction)
        ? LABELS.currentUser
        : reaction?.sender_name ||
          reaction?.senderName ||
          reaction?.display_name ||
          reaction?.displayName ||
          reactionSenderKey(reaction) ||
          LABELS.fallbackSender,
      isCurrentUser: isCurrentUserReaction(reaction),
    }))
    .filter(reaction => reaction.emoji)
);

const popoverPositionClass = computed(() =>
  props.orientation === ORIENTATION.RIGHT ? 'right-0' : 'left-0'
);

const toggle = () => {
  isOpen.value = !isOpen.value;
};

const close = () => {
  isOpen.value = false;
};

const handleDocumentClick = event => {
  if (!container.value?.contains(event.target)) close();
};

const removeCurrentUserReaction = () => {
  emit('remove');
  close();
};

onMounted(() => {
  document.addEventListener('click', handleDocumentClick);
});

onBeforeUnmount(() => {
  document.removeEventListener('click', handleDocumentClick);
});
</script>

<template>
  <span ref="container" class="relative inline-flex">
    <button
      type="button"
      class="skip-context-menu inline-flex items-center rounded-full bg-n-alpha-2 px-1.5 py-0.5 text-xs leading-none shadow-sm outline outline-1 outline-n-strong/20 transition hover:bg-n-alpha-3"
      @click.stop="toggle"
      @contextmenu.stop.prevent
    >
      {{ displayLabel }}
    </button>
    <div
      v-if="isOpen"
      class="skip-context-menu absolute bottom-full z-50 mb-2 min-w-64 rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm shadow-lg"
      :class="popoverPositionClass"
      @click.stop
      @contextmenu.stop.prevent
    >
      <div class="mb-3 text-sm font-semibold text-n-slate-12">
        {{ LABELS.title }}
      </div>
      <button
        v-for="reaction in normalizedReactions"
        :key="`${reaction.senderName}-${reaction.emoji}`"
        type="button"
        class="flex w-full items-center justify-between gap-3 rounded-md px-2 py-2 text-left transition"
        :class="
          reaction.isCurrentUser
            ? 'hover:bg-n-alpha-2'
            : 'cursor-default hover:bg-transparent'
        "
        @click="reaction.isCurrentUser && removeCurrentUserReaction()"
      >
        <span class="min-w-0">
          <span class="block truncate font-medium text-n-slate-12">
            {{ reaction.senderName }}
          </span>
          <span
            v-if="reaction.isCurrentUser"
            class="block truncate text-xs text-n-slate-11"
          >
            {{ LABELS.removeHint }}
          </span>
        </span>
        <span class="text-lg leading-none">{{ reaction.emoji }}</span>
      </button>
    </div>
  </span>
</template>
