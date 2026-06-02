<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import InboxesAPI from 'dashboard/api/inboxes';
import { whatsmeowConversationPath } from 'dashboard/helper/whatsmeowConversationHelper';

const ALL_INBOXES = 'all';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');

const selectedInboxId = ref(ALL_INBOXES);
const searchValue = ref('');
const groupsByInbox = ref({});
const loadingInboxIds = ref([]);
const openingGroupJid = ref('');
const isUpdatingIgnoreGroups = ref(false);

const whatsmeowInboxes = computed(() =>
  inboxes.value.filter(inbox => inbox.channel_type === 'Channel::Whatsmeow')
);

const selectedInbox = computed(() =>
  whatsmeowInboxes.value.find(
    inbox => String(inbox.id) === selectedInboxId.value
  )
);

const hasSpecificInbox = computed(() => selectedInboxId.value !== ALL_INBOXES);

const isLoading = computed(() => loadingInboxIds.value.length > 0);

const ignoreGroupsEnabled = computed(
  () => !!selectedInbox.value?.ignore_groups
);

const targetInboxes = computed(() => {
  if (hasSpecificInbox.value)
    return selectedInbox.value ? [selectedInbox.value] : [];
  return whatsmeowInboxes.value;
});

const allGroups = computed(() =>
  targetInboxes.value.flatMap(inbox =>
    (groupsByInbox.value[inbox.id] || []).map(group => ({ ...group, inbox }))
  )
);

const filteredGroups = computed(() => {
  const query = searchValue.value.trim().toLowerCase();
  if (!query) return allGroups.value;

  return allGroups.value.filter(({ name, jid, inbox }) =>
    [name, jid, inbox.name].some(value =>
      String(value || '')
        .toLowerCase()
        .includes(query)
    )
  );
});

const selectedInboxLabel = computed(() => {
  if (!hasSpecificInbox.value) {
    return t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.ALL_INBOXES');
  }
  return selectedInbox.value?.name || '';
});

const setLoading = (inboxId, value) => {
  const ids = new Set(loadingInboxIds.value);
  if (value) ids.add(inboxId);
  else ids.delete(inboxId);
  loadingInboxIds.value = Array.from(ids);
};

const fetchGroupsForInbox = async inbox => {
  if (!inbox?.id) return;

  setLoading(inbox.id, true);
  try {
    const { data } = await InboxesAPI.getWhatsmeowGroups(inbox.id);
    groupsByInbox.value = {
      ...groupsByInbox.value,
      [inbox.id]: data.groups || [],
    };
  } catch (error) {
    groupsByInbox.value = {
      ...groupsByInbox.value,
      [inbox.id]: [],
    };
    useAlert(
      t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.LOAD_ERROR', {
        inbox: inbox.name,
      })
    );
  } finally {
    setLoading(inbox.id, false);
  }
};

const fetchGroups = async () => {
  await Promise.all(targetInboxes.value.map(fetchGroupsForInbox));
};

const refreshGroups = async () => {
  await fetchGroups();
};

const updateIgnoreGroups = async value => {
  if (!selectedInbox.value || isUpdatingIgnoreGroups.value) return;

  isUpdatingIgnoreGroups.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: selectedInbox.value.id,
      formData: false,
      channel: { ignore_groups: value },
    });
    useAlert(t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.IGNORE_GROUPS_UPDATED'));
  } catch (error) {
    useAlert(t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.IGNORE_GROUPS_ERROR'));
  } finally {
    isUpdatingIgnoreGroups.value = false;
  }
};

const openGroupConversation = async group => {
  if (openingGroupJid.value) return;

  openingGroupJid.value = group.jid;
  try {
    const { data } = await InboxesAPI.createWhatsmeowGroupConversation(
      group.inbox.id,
      {
        group_jid: group.jid,
        group_name: group.name,
        profile_picture_url: group.profile_picture_url,
        participant_count: group.participant_count,
      }
    );
    const conversationId = data.conversation_id || data.id;
    await router.push({
      path: whatsmeowConversationPath({
        route,
        inboxId: group.inbox.id,
        conversationId,
      }),
    });
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.OPEN_ERROR')
    );
  } finally {
    openingGroupJid.value = '';
  }
};

watch(selectedInboxId, fetchGroups);

onMounted(async () => {
  if (!whatsmeowInboxes.value.length) {
    await store.dispatch('inboxes/get');
  }

  if (!whatsmeowInboxes.value.length) return;
  selectedInboxId.value = String(whatsmeowInboxes.value[0].id);
});
</script>

<template>
  <div class="flex flex-col gap-4 pt-4 pb-8">
    <div
      class="flex flex-col gap-3 rounded-lg border border-n-weak bg-n-surface-2 p-4"
    >
      <div class="flex flex-col gap-3 md:flex-row md:items-center">
        <div class="flex min-w-0 flex-1 items-center gap-3">
          <div
            class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-11"
          >
            <span class="i-lucide-users size-5" />
          </div>
          <div class="min-w-0">
            <h2 class="m-0 text-base font-semibold text-n-slate-12">
              {{ t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.TITLE') }}
            </h2>
            <p class="m-0 text-sm text-n-slate-11">
              {{
                t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.DESCRIPTION', {
                  inbox: selectedInboxLabel,
                })
              }}
            </p>
          </div>
        </div>

        <NextButton
          slate
          outline
          sm
          icon="i-lucide-refresh-cw"
          :label="t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.REFRESH')"
          :is-loading="isLoading"
          @click="refreshGroups"
        />
      </div>

      <div class="grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
        <label class="flex flex-col gap-1 text-sm font-medium text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.INBOX_LABEL') }}
          <select
            v-model="selectedInboxId"
            class="reset-base h-10 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
          >
            <option :value="ALL_INBOXES">
              {{ t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.ALL_INBOXES') }}
            </option>
            <option
              v-for="inbox in whatsmeowInboxes"
              :key="inbox.id"
              :value="String(inbox.id)"
            >
              {{ inbox.name }}
            </option>
          </select>
        </label>

        <label class="flex flex-col gap-1 text-sm font-medium text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.SEARCH_LABEL') }}
          <span class="relative">
            <span
              class="i-lucide-search pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
            />
            <input
              v-model="searchValue"
              type="search"
              class="reset-base h-10 w-full rounded-lg border border-n-weak bg-n-alpha-black2 py-2 pl-9 pr-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
              :placeholder="
                t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.SEARCH_PLACEHOLDER')
              "
            />
          </span>
        </label>
      </div>

      <div
        v-if="hasSpecificInbox"
        class="flex items-center justify-between gap-3 rounded-lg bg-n-alpha-1 px-3 py-2"
      >
        <div class="min-w-0">
          <p class="m-0 text-sm font-medium text-n-slate-12">
            {{ t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.IGNORE_GROUPS_TITLE') }}
          </p>
          <p class="m-0 text-xs text-n-slate-10">
            {{ t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.IGNORE_GROUPS_HINT') }}
          </p>
        </div>
        <Switch
          :model-value="ignoreGroupsEnabled"
          :disabled="isUpdatingIgnoreGroups"
          @update:model-value="updateIgnoreGroups"
        />
      </div>
    </div>

    <div
      v-if="isLoading && !allGroups.length"
      class="flex items-center justify-center py-14 text-n-slate-11"
    >
      <Spinner />
    </div>

    <div
      v-else-if="!whatsmeowInboxes.length"
      class="flex items-center justify-center rounded-lg border border-dashed border-n-weak py-12 text-sm text-n-slate-11"
    >
      {{ t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.NO_INBOXES') }}
    </div>

    <div
      v-else-if="!filteredGroups.length"
      class="flex items-center justify-center rounded-lg border border-dashed border-n-weak py-12 text-sm text-n-slate-11"
    >
      {{ t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.EMPTY') }}
    </div>

    <div v-else class="flex flex-col gap-3">
      <article
        v-for="group in filteredGroups"
        :key="`${group.inbox.id}-${group.jid}`"
        class="flex items-center gap-3 rounded-lg border border-n-weak bg-n-surface-2 p-4"
      >
        <Avatar
          :name="group.name"
          :src="group.profile_picture_url"
          :size="44"
        />

        <div class="min-w-0 flex-1">
          <div class="flex min-w-0 items-center gap-2">
            <h3 class="m-0 truncate text-base font-semibold text-n-slate-12">
              {{ group.name }}
            </h3>
            <span
              v-if="group.is_announce"
              class="rounded-md bg-n-amber-9/10 px-1.5 py-0.5 text-xs font-medium text-n-amber-11"
            >
              {{ t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.ADMINS_ONLY') }}
            </span>
          </div>
          <div
            class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-n-slate-10"
          >
            <span class="inline-flex min-w-0 items-center gap-1">
              <ChannelIcon :inbox="group.inbox" use-brand-icon class="size-4" />
              <span class="truncate">{{ group.inbox.name }}</span>
            </span>
            <span>
              {{
                t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.MEMBER_COUNT', {
                  count: group.participant_count || 0,
                })
              }}
            </span>
            <span class="truncate">{{ group.jid }}</span>
          </div>
        </div>

        <NextButton
          slate
          outline
          sm
          icon="i-ph-chat-circle-dots"
          :label="t('CONTACTS_LAYOUT.WHATSMEOW_GROUPS.OPEN_CONVERSATION')"
          :is-loading="openingGroupJid === group.jid"
          @click="openGroupConversation(group)"
        />
      </article>
    </div>
  </div>
</template>
