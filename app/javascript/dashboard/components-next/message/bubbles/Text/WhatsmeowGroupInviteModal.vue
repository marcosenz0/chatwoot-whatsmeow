<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  isOpen: {
    type: Boolean,
    default: false,
  },
  invite: {
    type: Object,
    default: () => ({}),
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  isJoining: {
    type: Boolean,
    default: false,
  },
  error: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['close', 'join']);
const { t } = useI18n();

const groupName = computed(
  () =>
    props.invite?.name ||
    props.invite?.group_name ||
    props.invite?.groupJid ||
    props.invite?.group_jid ||
    t('CONVERSATION.WHATSMEOW_GROUP_INVITE.UNKNOWN_GROUP')
);

const profilePictureUrl = computed(
  () =>
    props.invite?.profile_picture_url || props.invite?.profilePictureUrl || ''
);

const participantCount = computed(() =>
  Number(props.invite?.participant_count || props.invite?.participantCount || 0)
);

const participantLabel = computed(() => {
  if (!participantCount.value) {
    return t('CONVERSATION.WHATSMEOW_GROUP_INVITE.GROUP_INVITE');
  }

  return participantCount.value === 1
    ? t('CONVERSATION.WHATSMEOW_GROUP_INVITE.ONE_PARTICIPANT')
    : t('CONVERSATION.WHATSMEOW_GROUP_INVITE.PARTICIPANTS', {
        count: participantCount.value,
      });
});

const canJoin = computed(
  () => !props.isLoading && !props.error && !props.isJoining
);
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[100] flex items-center justify-center bg-modal-backdrop-light p-4 dark:bg-modal-backdrop-dark"
      tabindex="-1"
      @click.self="emit('close')"
      @keydown.esc="emit('close')"
    >
      <section
        class="relative w-full max-w-[22rem] overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 p-6 text-center shadow-xl"
        role="dialog"
        aria-modal="true"
        :aria-label="$t('CONVERSATION.WHATSMEOW_GROUP_INVITE.GROUP_INVITE')"
      >
        <button
          type="button"
          class="absolute right-4 top-4 inline-flex size-8 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :aria-label="$t('CONVERSATION.WHATSMEOW_GROUP_INVITE.CLOSE')"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-4" />
        </button>

        <div class="flex flex-col items-center">
          <div
            class="mb-4 flex size-20 items-center justify-center overflow-hidden rounded-full bg-n-alpha-2 text-n-slate-10"
          >
            <span
              v-if="isLoading"
              class="i-lucide-loader-circle size-7 animate-spin"
            />
            <img
              v-else-if="profilePictureUrl"
              :src="profilePictureUrl"
              :alt="groupName"
              class="size-full object-cover"
            />
            <span v-else class="i-lucide-users-round size-8" />
          </div>

          <template v-if="isLoading">
            <p class="m-0 text-sm font-medium text-n-slate-12">
              {{ $t('CONVERSATION.WHATSMEOW_GROUP_INVITE.LOADING') }}
            </p>
            <p class="m-0 mt-1 text-sm text-n-slate-11">
              {{ $t('CONVERSATION.WHATSMEOW_GROUP_INVITE.LOADING_HINT') }}
            </p>
          </template>

          <template v-else>
            <h3
              class="m-0 max-w-full truncate text-xl font-semibold text-n-slate-12"
            >
              {{ groupName }}
            </h3>
            <p class="m-0 mt-1 text-sm text-n-slate-11">
              {{ participantLabel }}
            </p>
            <p
              v-if="error"
              class="m-0 mt-4 rounded-lg border border-n-ruby-5 bg-n-ruby-3 px-3 py-2 text-sm text-n-ruby-11"
            >
              {{ error }}
            </p>
          </template>
        </div>

        <div class="mt-6 grid gap-2">
          <button
            type="button"
            class="inline-flex h-11 w-full items-center justify-center gap-2 rounded-lg bg-n-teal-9 px-4 text-sm font-semibold text-white hover:bg-n-teal-10 disabled:cursor-not-allowed disabled:opacity-60"
            :disabled="!canJoin"
            @click="emit('join')"
          >
            <span
              class="size-4"
              :class="
                isJoining
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-log-in'
              "
            />
            <span>{{ $t('CONVERSATION.WHATSMEOW_GROUP_INVITE.JOIN') }}</span>
          </button>
          <button
            type="button"
            class="inline-flex h-10 w-full items-center justify-center gap-2 rounded-lg border border-n-weak px-4 text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-2"
            @click="emit('close')"
          >
            <span class="i-lucide-x size-4" />
            <span>{{ $t('CONVERSATION.WHATSMEOW_GROUP_INVITE.CANCEL') }}</span>
          </button>
        </div>
      </section>
    </div>
  </Teleport>
</template>
