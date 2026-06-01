<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import {
  whatsmeowConversationPath,
  whatsmeowDirectConversationPayload,
} from 'dashboard/helper/whatsmeowConversationHelper';

import Avatar from 'next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  inboxId: { type: Number, required: true },
  groupJid: { type: String, required: true },
  groupName: { type: String, default: '' },
});

const emit = defineEmits(['close']);

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const isFetching = ref(false);
const isOpeningConversation = ref(false);
const members = ref([]);
const searchQuery = ref('');

const normalizedMembers = computed(() =>
  members.value.map(member => ({
    jid: member.jid || '',
    name:
      member.name || member.phone_number || member.phoneNumber || member.jid,
    phoneNumber: member.phone_number || member.phoneNumber || '',
    profilePictureUrl:
      member.profile_picture_url || member.profilePictureUrl || '',
    lidJid: member.lid_jid || member.lidJid || '',
    isAdmin: member.is_admin || member.isAdmin || false,
    isSuperAdmin: member.is_super_admin || member.isSuperAdmin || false,
    isSavedContact: member.is_saved_contact || member.isSavedContact || false,
  }))
);

const filteredMembers = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();
  if (!query) return normalizedMembers.value;

  return normalizedMembers.value.filter(member =>
    [member.name, member.phoneNumber, member.jid]
      .filter(Boolean)
      .some(value => value.toLowerCase().includes(query))
  );
});

const adminCount = computed(
  () =>
    normalizedMembers.value.filter(
      member => member.isAdmin || member.isSuperAdmin
    ).length
);

const memberCountLabel = computed(() =>
  t('CONVERSATION.WHATSMEOW_GROUP.MEMBERS_COUNT', {
    count: normalizedMembers.value.length,
  })
);

const adminCountLabel = computed(() =>
  t('CONVERSATION.WHATSMEOW_GROUP.ADMINS_COUNT', {
    count: adminCount.value,
  })
);

const subtitle = computed(() => props.groupName);

const close = () => emit('close');

const fetchMembers = async () => {
  if (!props.show || !props.groupJid || !props.inboxId) {
    isFetching.value = false;
    return;
  }

  isFetching.value = true;
  try {
    const { data } = await InboxesAPI.getWhatsmeowGroupMembers(
      props.inboxId,
      props.groupJid
    );
    members.value = data.members || [];
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CONVERSATION.WHATSMEOW_GROUP.MEMBERS_FAILED')
    );
  } finally {
    isFetching.value = false;
  }
};

const openPrivateConversation = async member => {
  if (isOpeningConversation.value) return;

  isOpeningConversation.value = true;
  try {
    const { data } = await InboxesAPI.createWhatsmeowDirectConversation(
      props.inboxId,
      whatsmeowDirectConversationPayload(member)
    );
    const conversationId = data.conversation_id || data.id;
    close();
    await router.push({
      path: whatsmeowConversationPath({
        route,
        inboxId: props.inboxId,
        conversationId,
      }),
    });
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CONVERSATION.WHATSMEOW_GROUP.OPEN_PRIVATE_CHAT_FAILED')
    );
  } finally {
    isOpeningConversation.value = false;
  }
};

watch(
  () => [props.show, props.groupJid],
  ([show]) => {
    if (show) {
      members.value = [];
      searchQuery.value = '';
      fetchMembers();
    }
  }
);
</script>

<template>
  <woot-modal
    :show="show"
    :on-close="close"
    size="medium"
    class="!items-start [&>div]:!top-12 [&>div]:sticky"
  >
    <div class="flex w-full flex-col gap-4 px-6 py-6">
      <div class="flex items-start justify-between gap-3 pr-8">
        <div class="min-w-0 flex-1">
          <h3 class="m-0 truncate text-lg font-semibold text-n-slate-12">
            {{ $t('CONVERSATION.WHATSMEOW_GROUP.MEMBERS_TITLE') }}
          </h3>
          <p v-if="subtitle" class="m-0 truncate text-sm text-n-slate-10">
            {{ subtitle }}
          </p>
          <div class="mt-2 flex flex-wrap items-center gap-2">
            <span
              class="rounded-md bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-11"
            >
              {{ memberCountLabel }}
            </span>
            <span
              class="rounded-md bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-11"
            >
              {{ adminCountLabel }}
            </span>
            <NextButton
              v-tooltip.top="$t('CONVERSATION.WHATSMEOW_GROUP.REFRESH_MEMBERS')"
              ghost
              slate
              xs
              icon="i-lucide-refresh-cw"
              :is-loading="isFetching"
              @click="fetchMembers"
            />
          </div>
        </div>
      </div>

      <div class="relative">
        <span
          class="i-lucide-search pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-9"
        />
        <input
          v-model="searchQuery"
          type="search"
          class="h-10 w-full rounded-lg border border-n-weak bg-n-alpha-2 ps-10 pe-3 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-9 focus:border-n-brand"
          :placeholder="$t('CONVERSATION.WHATSMEOW_GROUP.SEARCH_MEMBERS')"
        />
      </div>

      <div
        v-if="isFetching && !members.length"
        class="flex items-center justify-center gap-2 py-10 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
        {{ $t('CONVERSATION.WHATSMEOW_GROUP.LOADING_MEMBERS') }}
      </div>

      <div
        v-else-if="!filteredMembers.length"
        class="py-10 text-center text-sm text-n-slate-11"
      >
        {{ $t('CONVERSATION.WHATSMEOW_GROUP.NO_MEMBERS') }}
      </div>

      <div v-else class="max-h-[60vh] overflow-y-auto pr-1">
        <div
          v-for="member in filteredMembers"
          :key="member.jid || member.phoneNumber"
          class="flex items-center gap-3 rounded-lg px-2 py-2 hover:bg-n-alpha-2"
        >
          <Avatar
            :name="member.name"
            :src="member.profilePictureUrl"
            :size="36"
          />
          <div class="min-w-0 flex-1">
            <div class="flex min-w-0 items-center gap-1.5">
              <p class="m-0 truncate text-sm font-medium text-n-slate-12">
                {{ member.name }}
              </p>
              <span
                v-if="member.isSuperAdmin || member.isAdmin"
                class="shrink-0 rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-[11px] font-semibold uppercase text-n-slate-11"
              >
                {{
                  member.isSuperAdmin
                    ? $t('CONVERSATION.WHATSMEOW_GROUP.OWNER')
                    : $t('CONVERSATION.WHATSMEOW_GROUP.ADMIN')
                }}
              </span>
            </div>
            <p class="m-0 truncate text-xs text-n-slate-10">
              {{ member.phoneNumber || member.jid }}
            </p>
          </div>
          <NextButton
            v-tooltip.left="
              $t('CONVERSATION.WHATSMEOW_GROUP.OPEN_PRIVATE_CHAT')
            "
            ghost
            slate
            sm
            icon="i-ph-chat-circle-dots"
            :disabled="isOpeningConversation"
            @click="openPrivateConversation(member)"
          />
        </div>
      </div>
    </div>
  </woot-modal>
</template>
