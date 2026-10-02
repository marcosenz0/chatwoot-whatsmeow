<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { watchDebounced, useIntervalFn } from '@vueuse/core';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { useAlert } from 'dashboard/composables';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import StarredAPI from 'dashboard/api/whatsmeowStarredMessages';
import MessageAPI from 'dashboard/api/inbox/message';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'next/button/Button.vue';
import Input from 'next/input/Input.vue';
import Message from 'next/message/Message.vue';
import Spinner from 'next/spinner/Spinner.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const props = defineProps({ conversationId: { type: Number, default: null } });
const emit = defineEmits(['close']);
const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const request = useAbortableRequest();
const records = ref([]);
const query = ref('');
const inboxId = ref('');
const cursor = ref(null);
const pending = ref(0);
const syncing = ref(false);
const error = ref('');
const inboxes = computed(() =>
  store.getters['inboxes/getInboxes'].filter(
    i => i.channel_type === 'Channel::Whatsmeow'
  )
);
const currentUserId = computed(() => store.getters.getCurrentUserID);
const preview = message => useCamelCase(message, { deep: true });

async function load(more = false) {
  error.value = '';
  try {
    const response = await request.run(signal =>
      StarredAPI.get(
        {
          q: query.value,
          inbox_id: inboxId.value || undefined,
          conversation_id: props.conversationId || undefined,
          before: more ? cursor.value : undefined,
        },
        { signal }
      )
    );
    if (!response) return;
    records.value = more
      ? [...records.value, ...response.data.payload]
      : response.data.payload;
    cursor.value = response.data.next_cursor;
    pending.value = response.data.pending_count;
  } catch (e) {
    error.value = e.response?.data?.message || t('WHATSMEOW_UI.LOAD_ERROR');
  }
}

async function sync() {
  syncing.value = true;
  error.value = '';
  const targets = inboxId.value
    ? inboxes.value.filter(i => String(i.id) === inboxId.value)
    : inboxes.value;
  const results = await Promise.allSettled(
    targets.map(i => StarredAPI.sync(i.id))
  );
  const failures = results.filter(r => r.status === 'rejected');
  if (failures.length)
    error.value = t('WHATSMEOW_UI.SYNC_ERRORS', { count: failures.length });
  syncing.value = false;
  await load();
  if (failures.length)
    error.value = t('WHATSMEOW_UI.SYNC_ERRORS', { count: failures.length });
}

async function open(record, event) {
  if (event?.target.closest('a,button,audio,video,input')) return;
  await router.push({
    path: frontendURL(
      conversationUrl({
        accountId: route.params.accountId,
        id: record.conversation_id,
      })
    ),
    query: { messageId: String(record.message.id) },
  });
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: record.message.id,
    conversationId: record.conversation_id,
  });
}
async function unstar(record) {
  try {
    const { data } = await MessageAPI.star(
      record.conversation_id,
      record.message.id,
      false
    );
    await store.dispatch('updateMessage', data);
    records.value = records.value.filter(item => item.id !== record.id);
  } catch (e) {
    useAlert(e.response?.data?.message || t('WHATSMEOW_UI.SAVE_ERROR'));
  }
}
watchDebounced(query, () => load(), { debounce: 300 });
watch([inboxId, () => props.conversationId], () => load());
useIntervalFn(() => {
  if (pending.value && !syncing.value && !request.isPending.value) load();
}, 5000);
onMounted(async () => {
  await load();
  await sync();
});
</script>

<template>
  <section
    class="absolute inset-0 z-40 flex flex-col bg-n-surface-1 text-n-slate-12"
  >
    <header class="flex items-center gap-2 px-3 py-3 border-b border-n-weak">
      <Button
        type="button"
        icon="i-lucide-arrow-left"
        ghost
        slate
        sm
        :aria-label="$t('WHATSMEOW_UI.BACK')"
        @click="emit('close')"
      />
      <h2 class="m-0 flex-1 text-base font-semibold">
        {{ $t('WHATSMEOW_UI.STARRED_MESSAGES') }}
      </h2>
      <Button
        v-tooltip="$t('WHATSMEOW_UI.SYNC_STARS')"
        type="button"
        icon="i-lucide-refresh-cw"
        ghost
        slate
        sm
        :is-loading="syncing"
        :aria-label="$t('WHATSMEOW_UI.SYNC_STARS')"
        @click="sync"
      />
    </header>
    <div class="flex flex-col gap-2 p-3 border-b border-n-weak">
      <Input
        v-model="query"
        :placeholder="$t('WHATSMEOW_UI.SEARCH_MESSAGES')"
        size="sm"
      />
      <select
        v-model="inboxId"
        class="reset-base rounded-lg border border-n-weak bg-n-surface-2 p-2 text-sm"
        :aria-label="$t('WHATSMEOW_UI.INBOX')"
      >
        <option value="">{{ $t('WHATSMEOW_UI.ALL_INBOXES') }}</option>
        <option
          v-for="inbox in inboxes"
          :key="inbox.id"
          :value="String(inbox.id)"
        >
          {{ inbox.name }}
        </option>
      </select>
      <p v-if="pending" class="m-0 text-xs text-n-slate-11">
        {{ $t('WHATSMEOW_UI.PENDING_STARS', { count: pending }) }}
      </p>
      <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ error }}
      </p>
    </div>
    <div class="flex-1 min-h-0 overflow-y-auto">
      <div
        v-if="request.isPending.value && !records.length"
        class="flex justify-center p-6"
      >
        <Spinner />
      </div>
      <div
        v-else-if="!records.length"
        class="flex flex-col items-center gap-3 p-6 text-center text-n-slate-11"
      >
        <span class="i-lucide-star size-8" />
        <p>{{ $t('WHATSMEOW_UI.NO_STARS') }}</p>
        <Button
          type="button"
          :label="$t('WHATSMEOW_UI.SYNC_STARS')"
          :is-loading="syncing"
          @click="sync"
        />
      </div>
      <article
        v-for="record in records"
        :key="record.id"
        role="link"
        tabindex="0"
        class="group border-b border-n-weak px-3 py-4 cursor-pointer transition-colors hover:bg-n-alpha-2 focus:bg-n-alpha-2 outline-none"
        @click="open(record, $event)"
        @keydown.enter.prevent="open(record)"
      >
        <div class="flex items-center gap-2 mb-3">
          <Avatar
            :name="
              record.sender_name || record.sender_phone || record.chat_name
            "
            :src="record.avatar_url"
            :size="24"
            hide-offline-status
          />
          <span
            class="min-w-0 flex-1 truncate text-xs font-medium"
            :title="record.sender_name || record.sender_phone"
          >
            {{ record.sender_name || record.sender_phone }}
            <span
              class="i-lucide-chevron-right inline-block size-3 text-n-slate-10"
            />
            {{ record.chat_name }}
          </span>
          <span
            class="i-lucide-chevron-right size-3 shrink-0 text-n-slate-10"
          />
        </div>
        <div
          class="pointer-events-auto [&_.message-bubble]:max-w-full [&_img]:max-h-64 [&_video]:max-h-64"
        >
          <Message
            v-bind="preview(record.message)"
            :id="record.message.id"
            :conversation-id="record.conversation_id"
            :inbox-id="record.inbox_id"
            :current-user-id="currentUserId"
            is-preview
          />
        </div>
        <div
          class="mt-2 flex items-center justify-between gap-2 text-xxs text-n-slate-10"
        >
          <span class="truncate">{{ record.inbox_name }}</span>
          <Button
            type="button"
            icon="i-lucide-star-off"
            :label="$t('WHATSMEOW_UI.UNSTAR')"
            ghost
            slate
            xs
            @click.stop="unstar(record)"
          />
        </div>
      </article>
      <div v-if="cursor" class="flex justify-center p-3">
        <Button
          type="button"
          :label="$t('WHATSMEOW_UI.LOAD_MORE')"
          faded
          slate
          :is-loading="request.isPending.value"
          @click="load(true)"
        />
      </div>
    </div>
  </section>
</template>
