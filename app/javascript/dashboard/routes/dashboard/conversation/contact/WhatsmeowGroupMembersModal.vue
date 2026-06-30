<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import ContactsAPI from 'dashboard/api/contacts';
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
const isFetchingContacts = ref(false);
const isAddingMember = ref(false);
const members = ref([]);
const searchQuery = ref('');
const canAddMembers = ref(false);
const showAddMemberPanel = ref(false);
const addMemberQuery = ref('');
const contactOptions = ref([]);
const selectedContact = ref(null);
const isSelectingContact = ref(false);
let contactSearchTimer = null;

const contactPhone = contact =>
  contact.phone_number ||
  contact.phoneNumber ||
  contact.identifier ||
  contact.additional_attributes?.phone_number ||
  contact.additionalAttributes?.phoneNumber ||
  '';

const normalizeContact = contact => ({
  id: contact.id,
  name:
    contact.name ||
    contact.email ||
    contactPhone(contact) ||
    t('CONVERSATION.WHATSMEOW_GROUP.UNKNOWN_CONTACT'),
  phoneNumber: contactPhone(contact),
  thumbnail: contact.thumbnail || contact.avatar_url || contact.avatarUrl || '',
});

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
    isSelf: member.is_self || member.isSelf || false,
  }))
);

const memberSortRank = member => {
  if (member.isSelf) return 0;
  if (member.isSuperAdmin) return 1;
  if (member.isAdmin) return 2;
  return 3;
};

const sortedMembers = computed(() =>
  [...normalizedMembers.value].sort((left, right) => {
    const rankDiff = memberSortRank(left) - memberSortRank(right);
    if (rankDiff !== 0) return rankDiff;
    if (left.isSavedContact !== right.isSavedContact) {
      return left.isSavedContact ? -1 : 1;
    }
    return left.name.localeCompare(right.name);
  })
);

const filteredMembers = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();
  if (!query) return sortedMembers.value;

  return sortedMembers.value.filter(member =>
    [
      member.isSelf ? t('CONVERSATION.WHATSMEOW_GROUP.YOU') : '',
      member.name,
      member.phoneNumber,
      member.jid,
    ]
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

const memberDisplayName = member => member.name;

const csvValue = value => {
  const normalizedValue = `${value || ''}`
    .replace(/(\r\n|\n|\r)/gm, ' ')
    .trim();
  return `"${normalizedValue.replace(/"/g, '""')}"`;
};

const csvFilePart = value => {
  const normalizedValue = (value || 'grupo')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/gi, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase();

  return normalizedValue || 'grupo';
};

const memberRole = member => {
  if (member.isSuperAdmin) return t('CONVERSATION.WHATSMEOW_GROUP.OWNER');
  if (member.isAdmin) return t('CONVERSATION.WHATSMEOW_GROUP.ADMIN');

  return t('CONVERSATION.WHATSMEOW_GROUP.MEMBER');
};

const exportMembersCsv = () => {
  if (!normalizedMembers.value.length) {
    useAlert(t('CONVERSATION.WHATSMEOW_GROUP.EXPORT_CSV_EMPTY'));
    return;
  }

  const headers = [
    t('CONVERSATION.WHATSMEOW_GROUP.CSV_COLUMNS.NAME'),
    t('CONVERSATION.WHATSMEOW_GROUP.CSV_COLUMNS.PHONE'),
    t('CONVERSATION.WHATSMEOW_GROUP.CSV_COLUMNS.JID'),
    t('CONVERSATION.WHATSMEOW_GROUP.CSV_COLUMNS.LID'),
    t('CONVERSATION.WHATSMEOW_GROUP.CSV_COLUMNS.ROLE'),
    t('CONVERSATION.WHATSMEOW_GROUP.CSV_COLUMNS.SAVED_CONTACT'),
  ];

  const rows = normalizedMembers.value.map(member => [
    member.name,
    member.phoneNumber,
    member.jid,
    member.lidJid,
    memberRole(member),
    member.isSavedContact
      ? t('CONVERSATION.WHATSMEOW_GROUP.YES')
      : t('CONVERSATION.WHATSMEOW_GROUP.NO'),
  ]);

  const csvContent = [headers, ...rows]
    .map(row => row.map(csvValue).join(','))
    .join('\n');
  const blob = new Blob([`\uFEFF${csvContent}`], {
    type: 'text/csv;charset=utf-8;',
  });
  const url = window.URL.createObjectURL(blob);
  const link = document.createElement('a');

  link.href = url;
  link.download = `membros-${csvFilePart(props.groupName)}-${new Date()
    .toISOString()
    .slice(0, 10)}.csv`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.URL.revokeObjectURL(url);

  useAlert(
    t('CONVERSATION.WHATSMEOW_GROUP.EXPORT_CSV_SUCCESS', {
      count: normalizedMembers.value.length,
    })
  );
};

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
    canAddMembers.value = data.can_add_members || data.canAddMembers || false;
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CONVERSATION.WHATSMEOW_GROUP.MEMBERS_FAILED')
    );
  } finally {
    isFetching.value = false;
  }
};

const fetchContactOptions = async () => {
  if (!showAddMemberPanel.value) return;

  isFetchingContacts.value = true;
  try {
    const query = addMemberQuery.value.trim();
    const { data } = query
      ? await ContactsAPI.search(query, 1, 'name')
      : await ContactsAPI.get(1, 'name');
    contactOptions.value = (data.payload || [])
      .map(normalizeContact)
      .filter(contact => contact.phoneNumber);
  } catch (error) {
    contactOptions.value = [];
  } finally {
    isFetchingContacts.value = false;
  }
};

const scheduleContactSearch = () => {
  window.clearTimeout(contactSearchTimer);
  contactSearchTimer = window.setTimeout(fetchContactOptions, 300);
};

const selectContact = contact => {
  isSelectingContact.value = true;
  addMemberQuery.value = contact.phoneNumber;
  selectedContact.value = contact;
};

const clearAddMemberForm = () => {
  addMemberQuery.value = '';
  selectedContact.value = null;
  contactOptions.value = [];
};

const addGroupMember = async () => {
  const query = addMemberQuery.value.trim();
  if (isAddingMember.value || (!query && !selectedContact.value)) return;

  const participant = selectedContact.value?.phoneNumber || query;
  const payload = { group_jid: props.groupJid };
  if (participant.includes('@')) {
    payload.participant_jid = participant;
  } else {
    payload.participant_phone = participant;
  }

  isAddingMember.value = true;
  try {
    const { data } = await InboxesAPI.addWhatsmeowGroupMember(
      props.inboxId,
      payload
    );
    const addedMember =
      data.participant?.name || data.participant?.phone_number;
    useAlert(
      t('CONVERSATION.WHATSMEOW_GROUP.ADD_MEMBER_SUCCESS', {
        member: addedMember || participant,
      })
    );
    clearAddMemberForm();
    await fetchMembers();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error?.response?.data?.error ||
        t('CONVERSATION.WHATSMEOW_GROUP.ADD_MEMBER_FAILED')
    );
  } finally {
    isAddingMember.value = false;
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
      showAddMemberPanel.value = false;
      clearAddMemberForm();
      fetchMembers();
    }
  }
);

watch(showAddMemberPanel, showPanel => {
  if (showPanel) {
    fetchContactOptions();
  } else {
    clearAddMemberForm();
  }
});

watch(addMemberQuery, () => {
  if (isSelectingContact.value) {
    isSelectingContact.value = false;
  } else {
    selectedContact.value = null;
  }
  scheduleContactSearch();
});

onBeforeUnmount(() => {
  window.clearTimeout(contactSearchTimer);
});
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
        <NextButton
          v-if="canAddMembers"
          faded
          blue
          sm
          icon="i-lucide-user-plus"
          :label="$t('CONVERSATION.WHATSMEOW_GROUP.ADD_MEMBER')"
          @click="showAddMemberPanel = !showAddMemberPanel"
        />
      </div>

      <div
        v-if="showAddMemberPanel"
        class="rounded-lg border border-n-weak bg-n-alpha-2 p-3"
      >
        <div class="flex flex-col gap-3">
          <div class="relative">
            <span
              aria-hidden="true"
              class="i-lucide-search pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
            />
            <input
              v-model="addMemberQuery"
              type="search"
              class="h-10 w-full appearance-none rounded-lg border border-n-weak bg-n-solid-2 pl-3 pr-10 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-9 focus:border-n-brand"
              :placeholder="
                $t('CONVERSATION.WHATSMEOW_GROUP.ADD_MEMBER_PLACEHOLDER')
              "
            />
          </div>
          <div
            v-if="isFetchingContacts"
            class="flex items-center justify-center gap-2 py-4 text-sm text-n-slate-11"
          >
            <Spinner :size="16" />
            {{ $t('CONVERSATION.WHATSMEOW_GROUP.LOADING_CONTACTS') }}
          </div>
          <div
            v-else-if="contactOptions.length"
            class="max-h-44 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-1"
          >
            <button
              v-for="contact in contactOptions"
              :key="contact.id || contact.phoneNumber"
              type="button"
              class="flex w-full items-center gap-3 px-3 py-2 text-left hover:bg-n-alpha-2"
              @click="selectContact(contact)"
            >
              <Avatar
                :name="contact.name"
                :src="contact.thumbnail"
                :size="28"
              />
              <span class="min-w-0 flex-1">
                <span
                  class="block truncate text-sm font-medium text-n-slate-12"
                >
                  {{ contact.name }}
                </span>
                <span class="block truncate text-xs text-n-slate-10">
                  {{ contact.phoneNumber }}
                </span>
              </span>
            </button>
          </div>
          <div class="flex items-center justify-end gap-2">
            <NextButton
              ghost
              slate
              sm
              :label="$t('CONVERSATION.WHATSMEOW_GROUP.CANCEL')"
              @click="showAddMemberPanel = false"
            />
            <NextButton
              blue
              sm
              icon="i-lucide-user-plus"
              :label="$t('CONVERSATION.WHATSMEOW_GROUP.ADD_MEMBER_CONFIRM')"
              :is-loading="isAddingMember"
              :disabled="!addMemberQuery.trim() && !selectedContact"
              @click="addGroupMember"
            />
          </div>
        </div>
      </div>

      <div class="relative">
        <span
          aria-hidden="true"
          class="i-lucide-search pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
        />
        <input
          v-model="searchQuery"
          type="search"
          class="h-10 w-full appearance-none rounded-lg border border-n-weak bg-n-alpha-2 pl-3 pr-10 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-9 focus:border-n-brand"
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
            :name="memberDisplayName(member)"
            :src="member.profilePictureUrl"
            :size="36"
          />
          <div class="min-w-0 flex-1">
            <div class="flex min-w-0 items-center gap-1.5">
              <p class="m-0 truncate text-sm font-medium text-n-slate-12">
                {{ memberDisplayName(member) }}
              </p>
              <span
                v-if="member.isSelf"
                class="shrink-0 rounded-md bg-n-teal-4 px-1.5 py-0.5 text-[11px] font-semibold uppercase text-n-teal-11"
              >
                {{ $t('CONVERSATION.WHATSMEOW_GROUP.YOU') }}
              </span>
              <span
                v-if="member.isSelf || member.isSuperAdmin || member.isAdmin"
                class="shrink-0 rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-[11px] font-semibold uppercase text-n-slate-11"
              >
                {{ memberRole(member) }}
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

      <div class="flex items-center justify-end border-t border-n-weak pt-4">
        <NextButton
          faded
          blue
          sm
          icon="i-lucide-download"
          :label="$t('CONVERSATION.WHATSMEOW_GROUP.EXPORT_CSV')"
          :disabled="isFetching || !normalizedMembers.length"
          @click="exportMembersCsv"
        />
      </div>
    </div>
  </woot-modal>
</template>
