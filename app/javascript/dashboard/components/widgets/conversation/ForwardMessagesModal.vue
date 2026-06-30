<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  isOpen: {
    type: Boolean,
    default: false,
  },
  conversations: {
    type: Array,
    default: () => [],
  },
  currentUserId: {
    type: Number,
    default: null,
  },
  selectedCount: {
    type: Number,
    default: 0,
  },
  isForwarding: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'send']);
const { t, locale } = useI18n();

const query = ref('');
const activeTab = ref('all');
const selectedKeys = ref([]);

const isPortugueseLocale = computed(() =>
  String(locale.value || '')
    .toLowerCase()
    .startsWith('pt')
);

const forwardText = (key, params = {}) => {
  if (isPortugueseLocale.value) {
    if (key === 'ALL') return 'Todas';
    if (key === 'UNASSIGNED') return 'Não atribuídas';
    if (key === 'MINE') return 'Minhas';
    if (key === 'SEARCH') return 'Pesquisar nome ou número';
    if (key === 'MANUAL_NUMBER') return 'Enviar para este número';
    if (key === 'NO_RESULTS') return 'Nenhuma conversa encontrada';
    if (key === 'CONVERSATION') return 'Conversa';
    if (key === 'SEND') return 'Encaminhar';
    if (key === 'TITLE') return 'Encaminhar mensagens para';
    if (key === 'TARGET_COUNT') {
      const { count = 0 } = params;
      return count === 1
        ? '1 destinatário selecionado'
        : `${count} destinatários selecionados`;
    }
  }

  if (key === 'ALL') {
    return t('CONVERSATION.MESSAGE_SELECTION.FORWARD_MODAL.ALL');
  }
  if (key === 'UNASSIGNED') {
    return t('CONVERSATION.MESSAGE_SELECTION.FORWARD_MODAL.UNASSIGNED');
  }
  if (key === 'MINE') {
    return t('CONVERSATION.MESSAGE_SELECTION.FORWARD_MODAL.MINE');
  }
  if (key === 'SEARCH') {
    return t('CONVERSATION.MESSAGE_SELECTION.FORWARD_MODAL.SEARCH');
  }
  if (key === 'MANUAL_NUMBER') {
    return t('CONVERSATION.MESSAGE_SELECTION.FORWARD_MODAL.MANUAL_NUMBER');
  }
  if (key === 'NO_RESULTS') {
    return t('CONVERSATION.MESSAGE_SELECTION.FORWARD_MODAL.NO_RESULTS');
  }
  if (key === 'CONVERSATION') {
    return t('CONVERSATION.MESSAGE_SELECTION.FORWARD_MODAL.CONVERSATION');
  }
  if (key === 'TARGET_COUNT') {
    return t(
      'CONVERSATION.MESSAGE_SELECTION.FORWARD_MODAL.TARGET_COUNT',
      params
    );
  }
  if (key === 'SEND') {
    return t('CONVERSATION.MESSAGE_SELECTION.FORWARD_MODAL.SEND');
  }

  return t('CONVERSATION.MESSAGE_SELECTION.FORWARD_MODAL.TITLE', params);
};

const tabs = computed(() => [
  {
    key: 'all',
    label: forwardText('ALL'),
  },
  {
    key: 'unassigned',
    label: forwardText('UNASSIGNED'),
  },
  {
    key: 'mine',
    label: forwardText('MINE'),
  },
]);

watch(
  () => props.isOpen,
  value => {
    if (!value) {
      query.value = '';
      activeTab.value = 'all';
      selectedKeys.value = [];
    }
  }
);

const compactValue = value => String(value || '').trim();

const normalizePhoneNumber = value => {
  const digits = compactValue(value).replace(/\D/g, '');
  return digits ? `+${digits}` : '';
};

const conversationSender = conversation => conversation.meta?.sender || {};

const conversationName = conversation => {
  const sender = conversationSender(conversation);
  return (
    compactValue(sender.name) ||
    compactValue(sender.phone_number || sender.phoneNumber) ||
    compactValue(conversation.id)
  );
};

const conversationPhone = conversation => {
  const sender = conversationSender(conversation);
  const sourceId =
    conversation.contact_inbox?.source_id ||
    conversation.contactInbox?.sourceId ||
    '';
  return compactValue(sender.phone_number || sender.phoneNumber || sourceId);
};

const conversationSubtitle = conversation => {
  const sender = conversationSender(conversation);
  const parts = [
    conversationPhone(conversation),
    compactValue(sender.email),
    compactValue(conversation.inbox?.name),
  ].filter(Boolean);
  return parts.join(' - ');
};

const conversationAvatar = conversation => {
  const sender = conversationSender(conversation);
  return compactValue(
    sender.thumbnail || sender.avatar_url || sender.avatarUrl
  );
};

const assigneeId = conversation => conversation.meta?.assignee?.id;

const matchesActiveTab = conversation => {
  if (activeTab.value === 'unassigned') return !assigneeId(conversation);
  if (activeTab.value === 'mine') {
    return Number(assigneeId(conversation)) === Number(props.currentUserId);
  }
  return true;
};

const queryValue = computed(() => query.value.trim().toLowerCase());

const matchesQuery = conversation => {
  if (!queryValue.value) return true;

  return [
    conversationName(conversation),
    conversationPhone(conversation),
    conversationSubtitle(conversation),
  ]
    .join(' ')
    .toLowerCase()
    .includes(queryValue.value);
};

const visibleConversations = computed(() =>
  props.conversations
    .filter(conversation => conversation.id)
    .filter(matchesActiveTab)
    .filter(matchesQuery)
    .slice(0, 50)
);

const manualPhoneNumber = computed(() => normalizePhoneNumber(query.value));

const canUseManualPhone = computed(() => {
  const digits = manualPhoneNumber.value.replace(/\D/g, '');
  return digits.length >= 8;
});

const manualPhoneKey = computed(() => `phone:${manualPhoneNumber.value}`);

const conversationKey = conversation => `conversation:${conversation.id}`;

const isSelected = key => selectedKeys.value.includes(key);

const toggleKey = key => {
  selectedKeys.value = isSelected(key)
    ? selectedKeys.value.filter(selectedKey => selectedKey !== key)
    : [...selectedKeys.value, key];
};

const selectedTargets = computed(() =>
  selectedKeys.value
    .map(key => {
      if (key.startsWith('phone:')) {
        const phoneNumber = key.replace('phone:', '');
        return {
          type: 'phone',
          phoneNumber,
          label: phoneNumber,
        };
      }

      const conversationId = Number(key.replace('conversation:', ''));
      const conversation = props.conversations.find(
        item => Number(item.id) === conversationId
      );

      if (!conversation) return null;

      return {
        type: 'conversation',
        conversationId,
        label: conversationName(conversation),
      };
    })
    .filter(Boolean)
);

const send = () => {
  if (!selectedTargets.value.length || props.isForwarding) return;
  emit('send', selectedTargets.value);
};
</script>

<template>
  <div class="contents">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[100] flex items-start justify-center bg-modal-backdrop-light p-4 pt-12 dark:bg-modal-backdrop-dark"
      @click.self="emit('close')"
    >
      <section
        class="flex max-h-[84vh] w-full max-w-xl flex-col overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 shadow-xl"
      >
        <header class="flex items-center gap-3 border-b border-n-weak p-4">
          <NextButton
            ghost
            slate
            sm
            icon="i-lucide-x"
            :disabled="isForwarding"
            @click="emit('close')"
          />
          <div class="min-w-0 flex-1">
            <h3 class="m-0 truncate text-base font-semibold text-n-slate-12">
              {{
                forwardText('TITLE', {
                  count: selectedCount,
                })
              }}
            </h3>
          </div>
        </header>

        <div class="grid gap-3 border-b border-n-weak p-4">
          <label
            class="flex h-10 items-center gap-2 rounded-lg border border-n-weak bg-n-alpha-1 px-3 focus-within:border-n-brand"
          >
            <Icon icon="i-lucide-search" class="size-4 text-n-slate-10" />
            <input
              v-model="query"
              class="reset-base h-full min-w-0 flex-1 bg-transparent text-sm text-n-slate-12 outline-none"
              type="search"
              autocomplete="off"
              :placeholder="forwardText('SEARCH')"
            />
          </label>

          <div class="flex rounded-lg bg-n-alpha-1 p-1">
            <button
              v-for="tab in tabs"
              :key="tab.key"
              type="button"
              class="h-8 flex-1 rounded-md px-3 text-xs font-medium text-n-slate-11"
              :class="
                activeTab === tab.key
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'hover:bg-n-alpha-2'
              "
              @click="activeTab = tab.key"
            >
              {{ tab.label }}
            </button>
          </div>
        </div>

        <div class="min-h-64 flex-1 overflow-y-auto p-2">
          <button
            v-if="canUseManualPhone"
            type="button"
            class="mb-1 flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left hover:bg-n-alpha-2"
            @click="toggleKey(manualPhoneKey)"
          >
            <span
              class="grid size-4 shrink-0 place-content-center rounded border"
              :class="
                isSelected(manualPhoneKey)
                  ? 'border-n-brand bg-n-brand text-white'
                  : 'border-n-slate-8'
              "
            >
              <Icon
                v-if="isSelected(manualPhoneKey)"
                icon="i-lucide-check"
                class="size-3"
              />
            </span>
            <div
              class="grid size-10 shrink-0 place-content-center rounded-full bg-n-teal-9/15 text-n-teal-11"
            >
              <Icon icon="i-lucide-phone" class="size-4" />
            </div>
            <div class="min-w-0 flex-1">
              <p class="m-0 truncate text-sm font-medium text-n-slate-12">
                {{ manualPhoneNumber }}
              </p>
              <p class="m-0 truncate text-xs text-n-slate-11">
                {{ forwardText('MANUAL_NUMBER') }}
              </p>
            </div>
          </button>

          <div
            v-if="!visibleConversations.length && !canUseManualPhone"
            class="flex h-40 flex-col items-center justify-center gap-2 text-center text-sm text-n-slate-11"
          >
            <Icon icon="i-lucide-message-circle" class="size-8" />
            <p class="m-0">
              {{ forwardText('NO_RESULTS') }}
            </p>
          </div>

          <button
            v-for="conversation in visibleConversations"
            :key="conversation.id"
            type="button"
            class="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left hover:bg-n-alpha-2"
            @click="toggleKey(conversationKey(conversation))"
          >
            <span
              class="grid size-4 shrink-0 place-content-center rounded border"
              :class="
                isSelected(conversationKey(conversation))
                  ? 'border-n-brand bg-n-brand text-white'
                  : 'border-n-slate-8'
              "
            >
              <Icon
                v-if="isSelected(conversationKey(conversation))"
                icon="i-lucide-check"
                class="size-3"
              />
            </span>
            <Avatar
              :name="conversationName(conversation)"
              :src="conversationAvatar(conversation)"
              :size="40"
            />
            <div class="min-w-0 flex-1">
              <p class="m-0 truncate text-sm font-medium text-n-slate-12">
                {{ conversationName(conversation) }}
              </p>
              <p class="m-0 truncate text-xs text-n-slate-11">
                {{
                  conversationSubtitle(conversation) ||
                  forwardText('CONVERSATION')
                }}
              </p>
            </div>
          </button>
        </div>

        <footer
          class="flex items-center justify-between gap-3 border-t border-n-weak p-4"
        >
          <p class="m-0 truncate text-sm text-n-slate-11">
            {{
              forwardText('TARGET_COUNT', {
                count: selectedTargets.length,
              })
            }}
          </p>
          <NextButton
            solid
            blue
            icon="i-lucide-send"
            :label="forwardText('SEND')"
            :disabled="!selectedTargets.length"
            :is-loading="isForwarding"
            @click="send"
          />
        </footer>
      </section>
    </div>
  </div>
</template>
