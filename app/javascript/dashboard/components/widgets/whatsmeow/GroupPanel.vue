<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useEmitter } from 'dashboard/composables/emitter';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { useWhatsmeowPreferences } from 'dashboard/composables/useWhatsmeowPreferences';
import { whatsmeowGroupJid } from 'dashboard/helper/whatsmeowGroup';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useExpandableContent } from 'shared/composables/useExpandableContent';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import GroupsAPI from 'dashboard/api/whatsmeowGroups';
import InboxesAPI from 'dashboard/api/inboxes';
import MessageAPI from 'dashboard/api/inbox/message';
import Button from 'next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import Input from 'next/input/Input.vue';
import Dialog from 'next/dialog/Dialog.vue';
import Spinner from 'next/spinner/Spinner.vue';
import SharedFiles from 'dashboard/routes/dashboard/conversation/SharedFiles.vue';
import FormattedContent from 'dashboard/components-next/message/bubbles/Text/FormattedContent.vue';
import GroupSettings from './GroupSettings.vue';
import GroupMember from './GroupMember.vue';
import GroupContactPicker from './GroupContactPicker.vue';
import CreateGroupDialog from './CreateGroupDialog.vue';
import StarredMessagesPanel from './StarredMessagesPanel.vue';

const props = defineProps({ chat: { type: Object, required: true } });
const store = useStore();
const router = useRouter();
const { t } = useI18n();
const { updateUISettings } = useUISettings();
const prefs = useWhatsmeowPreferences();
const request = useAbortableRequest();
const group = ref(null);
const pendingOperation = ref('');
const error = ref('');
const busy = ref(false);
const dialog = ref(null);
const mode = ref('');
const settings = ref({});
const selected = ref([]);
const query = ref('');
const searchResults = ref([]);
const memberQuery = ref('');
const invite = ref('');
const joinRequests = ref([]);
const changes = ref([]);
const selectedMember = ref(null);
const communityJid = ref('');
const communities = ref([]);
const showStars = ref(false);
const showSimilar = ref(false);
const showMedia = ref(false);
const jid = computed(() => whatsmeowGroupJid(props.chat));
const {
  contentElement: descriptionElement,
  isExpanded: descriptionExpanded,
  needsToggle: canExpandDescription,
  toggleExpanded: toggleDescription,
  checkOverflow: checkDescriptionOverflow,
} = useExpandableContent({ maxLines: 3, useResizeObserverForCheck: true });
const memberRank = member => {
  if (member.is_super_admin) return 0;
  if (member.is_admin) return 1;
  if (member.is_self) return 2;
  return 3;
};
const sortedMembers = computed(() =>
  [...(group.value?.members || [])].sort(
    (left, right) =>
      memberRank(left) - memberRank(right) ||
      (left.name || left.phone_number).localeCompare(
        right.name || right.phone_number
      )
  )
);
const previewMembers = computed(() => sortedMembers.value.slice(0, 9));
const remainingMembers = computed(() =>
  Math.max(sortedMembers.value.length - 9, 0)
);
const members = computed(() => {
  const queryText = memberQuery.value.trim().toLowerCase();
  return sortedMembers.value.filter(member =>
    [
      member.is_self ? t('WHATSMEOW_UI.YOU') : '',
      member.name,
      member.phone_number,
    ].some(value => value?.toLowerCase().includes(queryText))
  );
});
const excluded = computed(
  () => group.value?.members.flatMap(m => [m.jid, m.lid_jid]) || []
);
const dialogTitle = computed(() =>
  t(
    mode.value === 'members'
      ? 'WHATSMEOW_UI.MEMBERS_TITLE'
      : `WHATSMEOW_UI.${mode.value.toUpperCase() || 'GROUP_INFO'}`
  )
);
const canCall = computed(
  () => group.value && group.value.count >= 3 && group.value.count <= 32
);
const showConfirm = computed(
  () =>
    (mode.value !== 'settings' || group.value?.can_edit) &&
    ![
      'members',
      'invite',
      'requests',
      'search',
      'changes',
      'encryption',
      'provider_limits',
    ].includes(mode.value)
);

async function load() {
  error.value = '';
  try {
    const response = await request.run(signal =>
      GroupsAPI.show(props.chat.inbox_id, jid.value, { signal })
    );
    if (response) {
      group.value = response.data;
    }
  } catch (e) {
    error.value = e.response?.data?.message || t('WHATSMEOW_UI.LOAD_ERROR');
  }
}
async function action(operation, participants = [], extra = {}) {
  const { data } = await GroupsAPI.action(props.chat.inbox_id, {
    group_jid: jid.value,
    operation,
    participants,
    ...extra,
  });
  const failures = (data.participants || []).filter(p => p.error);
  if (failures.length)
    throw new Error(
      t('WHATSMEOW_UI.MEMBER_ERRORS', {
        details: failures
          .map(p => `${p.name || p.phone_number || p.jid}: ${p.error}`)
          .join('; '),
      })
    );
  return data;
}
async function open(value, member = null) {
  mode.value = value;
  error.value = '';
  selectedMember.value = member;
  selected.value = [];
  settings.value = { ...group.value, name: group.value.group_name };
  query.value = '';
  memberQuery.value = '';
  searchResults.value = [];
  dialog.value.open();
  try {
    if (value === 'invite') invite.value = (await action('invite')).invite_link;
    if (value === 'requests')
      joinRequests.value = (
        await GroupsAPI.requests(props.chat.inbox_id, jid.value)
      ).data.requests;
    if (value === 'changes')
      changes.value = (
        await MessageAPI.groupChanges(props.chat.id)
      ).data.payload;
    if (value === 'community') {
      communityJid.value = '';
      communities.value = (
        await InboxesAPI.getWhatsmeowGroups(props.chat.inbox_id)
      ).data.groups.filter(g => g.is_community && g.self_is_admin);
    }
  } catch (e) {
    error.value = e.response?.data?.message || e.message;
  }
}
async function confirm() {
  busy.value = true;
  error.value = '';
  try {
    if (mode.value === 'settings') {
      const keys = group.value.self_is_admin
        ? [
            'name',
            'topic',
            'photo',
            'allow_member_edit',
            'allow_member_send',
            'allow_member_add',
            'require_approval',
            'disappearing_timer',
          ]
        : ['name', 'topic', 'photo', 'disappearing_timer'];
      const settingChanges = Object.fromEntries(
        keys
          .filter(
            key =>
              settings.value[key] !==
              (key === 'name' ? group.value.group_name : group.value[key])
          )
          .map(key => [key, settings.value[key]])
      );
      group.value = (
        await GroupsAPI.update(props.chat.inbox_id, {
          group_jid: jid.value,
          ...settingChanges,
        })
      ).data;
      await store.dispatch('getConversation', props.chat.id);
    } else if (mode.value === 'add') {
      await action(
        'add',
        selected.value.map(m => m.jid)
      );
      await load();
    } else if (['remove', 'promote', 'demote'].includes(mode.value)) {
      await action(mode.value, [selectedMember.value.jid]);
      await load();
    } else if (mode.value === 'leave') {
      await action('leave');
      await store.dispatch('toggleStatus', {
        conversationId: props.chat.id,
        status: 'resolved',
      });
      await updateUISettings({ is_contact_sidebar_open: false });
    } else if (mode.value === 'clear') {
      await prefs.set(props.chat.id, { cleared_before: Date.now() / 1000 });
    } else if (mode.value === 'community') {
      await action('link_community', [], { community_jid: communityJid.value });
      await load();
    }
    dialog.value.close();
    useAlert(t('WHATSMEOW_UI.SAVED'));
  } catch (e) {
    error.value =
      e.response?.data?.message || e.message || t('WHATSMEOW_UI.SAVE_ERROR');
  } finally {
    busy.value = false;
  }
}
async function resetInvite() {
  if (mode.value !== 'reset_invite') {
    mode.value = 'reset_invite';
    return;
  }
  busy.value = true;
  try {
    invite.value = (await action('reset_invite')).invite_link;
    mode.value = 'invite';
  } catch (e) {
    error.value = e.response?.data?.message || e.message;
  } finally {
    busy.value = false;
  }
}
async function moderate(member, operation) {
  busy.value = true;
  try {
    await action(operation, [member.jid]);
    joinRequests.value = (
      await GroupsAPI.requests(props.chat.inbox_id, jid.value)
    ).data.requests;
    await load();
  } catch (e) {
    error.value = e.response?.data?.message || e.message;
  } finally {
    busy.value = false;
  }
}
async function search() {
  busy.value = true;
  try {
    searchResults.value = (
      await MessageAPI.search(props.chat.id, query.value)
    ).data.payload;
  } catch (e) {
    error.value = e.response?.data?.message || e.message;
  } finally {
    busy.value = false;
  }
}
async function jump(message) {
  dialog.value.close();
  await router.push({
    path: frontendURL(
      conversationUrl({
        accountId: store.getters.getCurrentAccountId,
        id: props.chat.id,
      })
    ),
    query: { messageId: String(message.id) },
  });
  await store.dispatch('fetchPreviousMessages', {
    conversationId: props.chat.id,
    around: message.id,
  });
  await nextTick();
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: message.id,
    conversationId: props.chat.id,
  });
}
async function copyInvite() {
  await copyTextToClipboard(invite.value);
  useAlert(t('WHATSMEOW_UI.COPIED'));
}
async function mute() {
  await store.dispatch(
    props.chat.muted ? 'unmuteConversation' : 'muteConversation',
    props.chat.id
  );
}
async function exportChat() {
  try {
    const { data } = await MessageAPI.exportConversation(props.chat.id);
    const url = URL.createObjectURL(
      new Blob([data], { type: 'text/plain;charset=utf-8' })
    );
    const link = document.createElement('a');
    link.href = url;
    link.download = `${group.value.group_name.replace(/[^\p{L}\p{N} -]/gu, '') || 'WhatsApp'}.txt`;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  } catch (e) {
    useAlert(e.response?.data?.message || t('WHATSMEOW_UI.LOAD_ERROR'));
  }
}
function call(video) {
  emitter.emit(BUS_EVENTS.WHATSMEOW_START_CALL, {
    conversationId: props.chat.id,
    video,
  });
}
function selectMessages() {
  emitter.emit(BUS_EVENTS.WHATSMEOW_SELECT_MESSAGES, {
    conversationId: props.chat.id,
  });
}
const quickActions = computed(() => [
  ...(canCall.value
    ? [
        { icon: 'i-lucide-phone', label: 'VOICE', action: () => call(false) },
        { icon: 'i-lucide-video', label: 'VIDEO', action: () => call(true) },
      ]
    : []),
  {
    icon: 'i-lucide-user-plus',
    label: 'ADD_SHORT',
    ariaLabel: 'ADD',
    disabled: !group.value?.can_add_members,
    action: () => open('add'),
  },
  { icon: 'i-lucide-search', label: 'SEARCH', action: () => open('search') },
]);
watch(group, value => {
  if (!value || !pendingOperation.value) return;
  const operation = pendingOperation.value;
  pendingOperation.value = '';
  open(operation);
});
watch(
  () => group.value?.topic,
  async () => {
    descriptionExpanded.value = false;
    canExpandDescription.value = false;
    await nextTick();
    checkDescriptionOverflow();
  }
);
useEmitter(
  BUS_EVENTS.WHATSMEOW_GROUP_ACTION,
  ({ conversationId, operation }) => {
    if (conversationId !== props.chat.id) return;
    if (group.value) open(operation);
    else pendingOperation.value = operation;
  }
);
watch(
  () => props.chat.id,
  () => {
    group.value = null;
    pendingOperation.value = '';
    showStars.value = false;
    showMedia.value = false;
    memberQuery.value = '';
    dialog.value?.close();
    load();
  }
);
onMounted(load);
</script>

<template>
  <section
    class="relative flex flex-col w-full h-full min-h-0 min-w-0 text-n-slate-12"
  >
    <header
      class="flex items-center gap-2 p-3 border-b border-n-weak sticky top-0 z-10 bg-n-surface-2"
    >
      <Button
        type="button"
        icon="i-lucide-x"
        ghost
        slate
        sm
        :aria-label="$t('WHATSMEOW_UI.CLOSE')"
        @click="updateUISettings({ is_contact_sidebar_open: false })"
      />
      <h2 class="m-0 flex-1 text-base font-medium">
        {{ $t('WHATSMEOW_UI.GROUP_INFO') }}
      </h2>
      <Button
        type="button"
        icon="i-lucide-refresh-cw"
        ghost
        slate
        sm
        :aria-label="$t('WHATSMEOW_UI.REFRESH')"
        @click="load"
      />
    </header>
    <p v-if="error && !mode" role="alert" class="m-3 text-sm text-n-ruby-11">
      {{ error }}
    </p>
    <div
      v-if="!group && request.isPending.value"
      class="flex justify-center p-6"
    >
      <Spinner />
    </div>
    <div v-if="group" class="min-h-0 flex-1 overflow-y-auto">
      <div class="flex flex-col items-center gap-2 px-5 py-5">
        <button
          type="button"
          class="p-0"
          :disabled="!group.can_edit"
          :aria-label="$t('WHATSMEOW_UI.GROUP_PHOTO')"
          @click="open('settings')"
        >
          <Avatar
            :name="group.group_name"
            :src="chat.meta.sender.thumbnail || group.profile_picture_url"
            :size="96"
            hide-offline-status
          />
        </button>
        <div class="flex w-full min-w-0 items-start justify-center gap-2 mt-2">
          <h3
            class="m-0 min-w-0 text-center text-xl font-medium leading-tight break-words [overflow-wrap:anywhere]"
          >
            {{ group.group_name }}
          </h3>
          <Button
            v-if="group.can_edit"
            type="button"
            icon="i-lucide-pencil"
            ghost
            slate
            xs
            class="shrink-0"
            :aria-label="$t('WHATSMEOW_UI.GROUP_NAME')"
            @click="open('settings')"
          />
        </div>
        <p class="m-0 text-sm text-n-slate-11">
          {{ $t('WHATSMEOW_UI.MEMBERS', { count: group.count }) }}
        </p>
        <div
          class="flex w-full max-w-xs items-start justify-center gap-1 mt-2"
          data-group-quick-actions
        >
          <button
            v-for="item in quickActions"
            :key="item.label"
            type="button"
            class="group/action flex min-w-0 flex-1 flex-col items-center gap-1.5 rounded-lg p-0 text-xs text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:opacity-40"
            :aria-label="$t(`WHATSMEOW_UI.${item.ariaLabel || item.label}`)"
            :disabled="item.disabled"
            @click="item.action"
          >
            <span
              class="flex h-11 w-14 max-w-full items-center justify-center rounded-full bg-n-alpha-2 transition-colors group-hover/action:bg-n-alpha-3"
            >
              <span :class="item.icon" class="size-5 shrink-0" />
            </span>
            <span
              class="w-full whitespace-nowrap text-center leading-4 tracking-tight"
            >
              {{ $t(`WHATSMEOW_UI.${item.label}`) }}
            </span>
          </button>
        </div>
      </div>
      <div class="px-5 pb-5 border-b border-n-weak">
        <div class="flex items-start gap-2">
          <div class="min-w-0 flex-1">
            <p
              v-if="group.topic"
              :id="`group-description-${chat.id}`"
              ref="descriptionElement"
              class="m-0 whitespace-pre-wrap break-words text-sm leading-6 text-n-slate-12 [overflow-wrap:anywhere]"
              :class="{ 'line-clamp-3': !descriptionExpanded }"
            >
              <FormattedContent
                :content="group.topic"
                :inbox-id="chat.inbox_id"
                plain-text
                @navigate="dialog?.close()"
              />
            </p>
            <button
              v-if="canExpandDescription"
              type="button"
              class="mt-1 rounded p-0 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :aria-expanded="descriptionExpanded"
              :aria-controls="`group-description-${chat.id}`"
              @click="toggleDescription()"
            >
              {{
                $t(
                  descriptionExpanded
                    ? 'WHATSMEOW_UI.READ_LESS'
                    : 'WHATSMEOW_UI.READ_MORE'
                )
              }}
            </button>
            <button
              v-else-if="!group.topic && group.can_edit"
              type="button"
              class="rounded p-0 text-sm text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              @click="open('settings')"
            >
              {{ $t('WHATSMEOW_UI.ADD_DESCRIPTION') }}
            </button>
          </div>
          <Button
            v-if="group.topic && group.can_edit"
            type="button"
            icon="i-lucide-pencil"
            ghost
            slate
            xs
            class="shrink-0"
            :aria-label="$t('WHATSMEOW_UI.DESCRIPTION')"
            @click="open('settings')"
          />
        </div>
      </div>
      <div class="flex flex-col gap-1 p-3 border-b border-n-weak">
        <Button
          type="button"
          icon="i-lucide-images"
          :label="$t('WHATSMEOW_UI.MEDIA_LINKS_DOCS')"
          ghost
          slate
          class="justify-start"
          @click="
            showMedia = !showMedia;
            store.dispatch('fetchAllAttachments', chat.id);
          "
        />
        <SharedFiles v-if="showMedia" />
        <Button
          type="button"
          icon="i-lucide-star"
          :label="$t('WHATSMEOW_UI.STARRED_MESSAGES')"
          ghost
          slate
          class="justify-start"
          @click="showStars = true"
        />
        <Button
          type="button"
          :icon="chat.muted ? 'i-lucide-volume-2' : 'i-lucide-bell-off'"
          :label="$t(chat.muted ? 'WHATSMEOW_UI.UNMUTE' : 'WHATSMEOW_UI.MUTE')"
          ghost
          slate
          class="justify-start"
          @click="mute"
        />
        <Button
          type="button"
          icon="i-lucide-lock-keyhole"
          :label="$t('WHATSMEOW_UI.ENCRYPTION')"
          ghost
          slate
          class="justify-start"
          @click="open('encryption')"
        />
        <Button
          type="button"
          icon="i-lucide-timer"
          :label="`${$t('WHATSMEOW_UI.DISAPPEARING_MESSAGES')} · ${$t(`WHATSMEOW_UI.DURATION_${group.disappearing_timer}`)}`"
          ghost
          slate
          class="justify-start"
          :disabled="!group.can_edit"
          @click="open('settings')"
        />
        <Button
          type="button"
          icon="i-lucide-settings"
          :label="$t('WHATSMEOW_UI.GROUP_PERMISSIONS')"
          ghost
          slate
          class="justify-start"
          @click="open('settings')"
        />
        <Button
          v-if="group.self_is_admin"
          type="button"
          icon="i-lucide-user-check"
          :label="$t('WHATSMEOW_UI.REQUESTS')"
          ghost
          slate
          class="justify-start"
          @click="open('requests')"
        />
        <Button
          v-if="group.self_is_admin && !group.is_community"
          type="button"
          icon="i-lucide-users"
          :label="$t('WHATSMEOW_UI.COMMUNITY')"
          ghost
          slate
          class="justify-start"
          @click="open('community')"
        />
        <Button
          type="button"
          icon="i-lucide-copy-plus"
          :label="$t('WHATSMEOW_UI.SIMILAR_GROUP')"
          ghost
          slate
          class="justify-start"
          @click="showSimilar = true"
        />
      </div>
      <div class="p-3 border-b border-n-weak flex flex-col gap-2">
        <div class="flex items-center justify-between gap-2">
          <span class="text-sm font-medium">
            {{ $t('WHATSMEOW_UI.MEMBER_COUNT', { count: group.count }) }}
          </span>
          <Button
            type="button"
            icon="i-lucide-search"
            ghost
            slate
            sm
            :aria-label="$t('WHATSMEOW_UI.SEARCH_MEMBERS')"
            @click="open('members')"
          />
        </div>
        <Button
          v-if="group.can_add_members"
          type="button"
          icon="i-lucide-user-plus"
          :label="$t('WHATSMEOW_UI.ADD')"
          ghost
          class="justify-start"
          @click="open('add')"
        />
        <Button
          type="button"
          icon="i-lucide-link"
          :label="$t('WHATSMEOW_UI.INVITE')"
          ghost
          class="justify-start"
          @click="open('invite')"
        />
        <GroupMember
          v-for="member in previewMembers"
          :key="member.jid"
          :member="member"
          :can-manage="group.self_is_admin"
          @action="open"
        />
        <Button
          v-if="remainingMembers"
          type="button"
          ghost
          :label="
            $t('WHATSMEOW_UI.VIEW_ALL_MEMBERS', { count: remainingMembers })
          "
          class="justify-start"
          @click="open('members')"
        />
      </div>
      <div class="flex flex-col gap-1 p-3">
        <Button
          type="button"
          icon="i-lucide-list"
          :label="$t('WHATSMEOW_UI.CHANGES')"
          ghost
          slate
          class="justify-start"
          @click="open('changes')"
        />
        <Button
          type="button"
          icon="i-lucide-download"
          :label="$t('WHATSMEOW_UI.EXPORT')"
          ghost
          slate
          class="justify-start"
          @click="exportChat"
        />
        <Button
          type="button"
          icon="i-lucide-square-check"
          :label="$t('WHATSMEOW_UI.SELECT_MESSAGES')"
          ghost
          slate
          class="justify-start"
          @click="selectMessages"
        />
        <Button
          type="button"
          icon="i-lucide-eraser"
          :label="$t('WHATSMEOW_UI.CLEAR')"
          ghost
          slate
          class="justify-start"
          @click="open('clear')"
        />
        <Button
          type="button"
          icon="i-lucide-log-out"
          :label="$t('WHATSMEOW_UI.LEAVE')"
          ghost
          ruby
          class="justify-start"
          @click="open('leave')"
        />
        <Button
          type="button"
          icon="i-lucide-shield"
          :label="$t('WHATSMEOW_UI.PROVIDER_LIMITS')"
          ghost
          slate
          class="justify-start"
          @click="open('provider_limits')"
        />
        <p class="px-2 text-xs text-n-slate-10">
          {{
            $t('WHATSMEOW_UI.CREATED_AT', {
              date: new Date(group.created_at * 1000).toLocaleString(),
            })
          }}
        </p>
      </div>
    </div>
    <StarredMessagesPanel
      v-if="showStars"
      :conversation-id="chat.id"
      @close="showStars = false"
    />
    <CreateGroupDialog
      v-if="showSimilar"
      :inbox-id="chat.inbox_id"
      :participants="group.members.filter(m => !m.is_self)"
      @close="showSimilar = false"
    />
    <Dialog
      ref="dialog"
      :title="dialogTitle"
      :type="['leave', 'remove', 'clear'].includes(mode) ? 'alert' : 'edit'"
      :is-loading="busy"
      :prevent-close="busy"
      :show-confirm-button="showConfirm"
      :disable-confirm-button="
        (mode === 'add' && !selected.length) ||
        (mode === 'community' && !communityJid) ||
        (mode === 'settings' && !settings.name?.trim())
      "
      @confirm="mode === 'reset_invite' ? resetInvite() : confirm()"
      @close="
        mode = '';
        error = '';
      "
    >
      <div
        class="max-h-[65vh] flex flex-col gap-3"
        :class="mode === 'members' ? 'overflow-hidden' : 'overflow-auto'"
      >
        <GroupSettings
          v-if="mode === 'settings'"
          v-model="settings"
          :can-edit="group.can_edit"
          :can-manage="group.self_is_admin"
          :inbox-id="chat.inbox_id"
          @navigate="dialog.close()"
        />
        <template v-if="mode === 'members'">
          <Input
            v-model="memberQuery"
            type="search"
            :placeholder="$t('WHATSMEOW_UI.SEARCH_MEMBERS')"
          />
          <p v-if="!members.length" class="m-0 text-sm text-n-slate-11">
            {{ $t('WHATSMEOW_UI.NO_MEMBERS') }}
          </p>
          <div class="min-h-0 overflow-y-auto" data-group-members-list>
            <GroupMember
              v-for="member in members"
              :key="member.jid"
              :member="member"
              :can-manage="group.self_is_admin"
              @action="open"
            />
          </div>
        </template>
        <GroupContactPicker
          v-if="mode === 'add'"
          v-model="selected"
          :inbox-id="chat.inbox_id"
          :excluded="excluded"
        />
        <template
          v-if="
            [
              'remove',
              'promote',
              'demote',
              'leave',
              'clear',
              'reset_invite',
            ].includes(mode)
          "
        >
          <p>
            {{
              $t(`WHATSMEOW_UI.${mode.toUpperCase()}_CONFIRM`, {
                name:
                  selectedMember?.name ||
                  selectedMember?.phone_number ||
                  group?.group_name,
              })
            }}
          </p>
        </template>
        <template v-if="mode === 'invite'">
          <Input :model-value="invite" readonly />
          <Button
            type="button"
            :label="$t('WHATSMEOW_UI.COPY_LINK')"
            icon="i-lucide-copy"
            @click="copyInvite"
          />
          <Button
            v-if="group.self_is_admin"
            type="button"
            :label="$t('WHATSMEOW_UI.RESET_INVITE')"
            faded
            ruby
            @click="resetInvite"
          />
        </template>
        <template v-if="mode === 'requests'">
          <p v-if="!joinRequests.length">
            {{ $t('WHATSMEOW_UI.NO_REQUESTS') }}
          </p>
          <div
            v-for="entry in joinRequests"
            :key="entry.member.jid"
            class="flex gap-2 items-center"
          >
            <span class="flex-1">
              {{ entry.member.name || entry.member.phone_number }}
            </span>
            <Button
              type="button"
              icon="i-lucide-check"
              :aria-label="$t('WHATSMEOW_UI.APPROVE')"
              :disabled="busy"
              @click="moderate(entry.member, 'approve')"
            />
            <Button
              type="button"
              icon="i-lucide-x"
              :aria-label="$t('WHATSMEOW_UI.REJECT')"
              ruby
              :disabled="busy"
              @click="moderate(entry.member, 'reject')"
            />
          </div>
        </template>
        <template v-if="mode === 'search'">
          <Input
            v-model="query"
            :placeholder="$t('WHATSMEOW_UI.SEARCH_MESSAGES')"
            @keydown.enter.prevent="search"
          />
          <Button
            type="button"
            :label="$t('WHATSMEOW_UI.SEARCH')"
            :is-loading="busy"
            :disabled="!query.trim()"
            @click="search"
          />
          <button
            v-for="message in searchResults"
            :key="message.id"
            type="button"
            class="text-start p-3 rounded-lg bg-n-alpha-1 hover:bg-n-alpha-2 text-sm"
            @click="jump(message)"
          >
            {{ message.content }}
            <span class="block text-xs text-n-slate-10">
              {{ new Date(message.created_at * 1000).toLocaleString() }}
            </span>
          </button>
        </template>
        <template v-if="mode === 'changes'">
          <p v-if="!changes.length">{{ $t('WHATSMEOW_UI.NO_CHANGES') }}</p>
          <p v-for="message in changes" :key="message.id" class="text-sm">
            {{ message.content }}
            <time class="block text-xs text-n-slate-10">
              {{ new Date(message.created_at * 1000).toLocaleString() }}
            </time>
          </p>
        </template>
        <label v-if="mode === 'community'" class="flex flex-col gap-2 text-sm">
          {{ $t('WHATSMEOW_UI.COMMUNITY_HELP') }}
          <select
            v-model="communityJid"
            class="reset-base rounded-lg bg-n-surface-1 border border-n-weak p-2"
          >
            <option disabled value="">
              {{ $t('WHATSMEOW_UI.COMMUNITY') }}
            </option>
            <option
              v-for="community in communities"
              :key="community.jid"
              :value="community.jid"
            >
              {{ community.name }}
            </option>
          </select>
        </label>
        <p v-if="mode === 'encryption'" class="text-sm">
          {{ $t('WHATSMEOW_UI.ENCRYPTION_HELP') }}
        </p>
        <p v-if="mode === 'provider_limits'" class="text-sm">
          {{ $t('WHATSMEOW_UI.PROVIDER_LIMITS_HELP') }}
        </p>
        <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
          {{ error }}
        </p>
      </div>
    </Dialog>
  </section>
</template>
