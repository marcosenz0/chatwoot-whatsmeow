<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ContactAPI from 'dashboard/api/contacts';
import WhatsmeowCallsAPI from 'dashboard/api/whatsmeowCalls';

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const currentUser = useMapGetter('getCurrentUser');
const whatsmeowInboxes = computed(() =>
  inboxes.value.filter(inbox => inbox.channel_type === 'Channel::Whatsmeow')
);
const calls = ref([]);
const favorites = ref([]);
const search = ref('');
const contactSearch = ref('');
const contacts = ref([]);
const mode = ref('home');
const selectedInboxId = ref('');
const phone = ref('');
const video = ref(false);
const link = ref('');
const scheduledAt = ref('');
const duration = ref(30);
const loading = ref(false);
const acting = ref(false);
let pollTimer;

const favoriteStorageKey = computed(
  () =>
    `whatsmeow-call-favorites:${route.params.accountId}:${currentUser.value?.id}`
);
const filteredCalls = computed(() =>
  calls.value.filter(call =>
    [call.name, call.phone_number, call.inbox_name]
      .filter(Boolean)
      .some(value => value.toLowerCase().includes(search.value.toLowerCase()))
  )
);
const filteredFavorites = computed(() =>
  favorites.value.filter(item =>
    [item.name, item.phone_number, item.inbox_name]
      .filter(Boolean)
      .some(value => value.toLowerCase().includes(search.value.toLowerCase()))
  )
);
const selectedInbox = computed(() =>
  whatsmeowInboxes.value.find(
    inbox => String(inbox.id) === String(selectedInboxId.value)
  )
);
const formatTime = value =>
  new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));
const callLabel = call => {
  if (call.status === 'missed') return t('WHATSAPP_CALLS.MISSED');
  if (call.status === 'unanswered') return t('WHATSAPP_CALLS.UNANSWERED');
  if (call.status === 'declined') return t('WHATSAPP_CALLS.DECLINED');
  if (call.status === 'connected') return t('WHATSAPP_CALLS.CONNECTED');
  if (call.status === 'ringing') return t('WHATSAPP_CALLS.RINGING');
  return call.direction === 'incoming'
    ? t('WHATSAPP_CALLS.INCOMING')
    : t('WHATSAPP_CALLS.OUTGOING');
};
const callIcon = call => {
  if (call.video) return 'i-lucide-video';
  return call.direction === 'incoming'
    ? 'i-lucide-phone-incoming'
    : 'i-lucide-phone-outgoing';
};
const callDuration = seconds => {
  const minutes = Math.floor(seconds / 60);
  return `${minutes}:${String(seconds % 60).padStart(2, '0')}`;
};
const favoriteKey = item => `${item.inbox_id}:${item.phone_number}`;
const isFavorite = item =>
  favorites.value.some(favorite => favoriteKey(favorite) === favoriteKey(item));

const fetchCalls = async () => {
  try {
    const { data } = await WhatsmeowCallsAPI.getAll();
    calls.value = data.payload;
  } catch {
    useAlert(t('WHATSAPP_CALLS.ERROR'));
  } finally {
    loading.value = false;
  }
};
const saveFavorites = () => {
  localStorage.setItem(
    favoriteStorageKey.value,
    JSON.stringify(favorites.value)
  );
};
const toggleFavorite = item => {
  const normalized = {
    inbox_id: item.inbox_id || selectedInboxId.value,
    inbox_name: item.inbox_name || selectedInbox.value?.name,
    phone_number: item.phone_number,
    name: item.name || item.phone_number,
    avatar_url: item.avatar_url || item.thumbnail || '',
    conversation_id: item.conversation_id,
  };
  if (!normalized.phone_number || !normalized.inbox_id) return;
  favorites.value = isFavorite(normalized)
    ? favorites.value.filter(
        favorite => favoriteKey(favorite) !== favoriteKey(normalized)
      )
    : [...favorites.value, normalized];
  saveFavorites();
  if (mode.value === 'favorite') mode.value = 'home';
};
const selectMode = value => {
  mode.value = value;
  link.value = '';
  contacts.value = [];
  contactSearch.value = '';
};
const startCall = async (item, withVideo = false) => {
  if (!item.inbox_id || (!item.phone_number && !item.conversation_id)) {
    useAlert(t('WHATSAPP_CALLS.PHONE'));
    return;
  }
  acting.value = true;
  try {
    let conversationId = item.conversation_id;
    if (!conversationId) {
      const { data } = await WhatsmeowCallsAPI.dial(
        item.inbox_id,
        item.phone_number
      );
      conversationId = data.payload.conversation_id;
    }
    await router.push({
      name: 'inbox_conversation',
      params: {
        accountId: route.params.accountId,
        conversation_id: conversationId,
      },
      query: { whatsmeowCall: withVideo ? 'video' : 'voice' },
    });
  } catch {
    useAlert(t('WHATSAPP_CALLS.ERROR'));
  } finally {
    acting.value = false;
  }
};
const callPhone = withVideo =>
  startCall(
    { inbox_id: selectedInboxId.value, phone_number: phone.value },
    withVideo
  );
const searchContacts = async () => {
  if (!contactSearch.value.trim()) return;
  acting.value = true;
  try {
    const { data } = await ContactAPI.search(contactSearch.value.trim());
    contacts.value = data.payload.filter(contact => contact.phone_number);
  } catch {
    useAlert(t('WHATSAPP_CALLS.ERROR'));
  } finally {
    acting.value = false;
  }
};
const contactItem = contact => ({
  inbox_id: selectedInboxId.value,
  phone_number: contact.phone_number,
  name: contact.name,
  avatar_url: contact.thumbnail,
});
const createLink = async () => {
  if (!selectedInboxId.value) return;
  acting.value = true;
  try {
    const { data } = await WhatsmeowCallsAPI.createLink(
      selectedInboxId.value,
      video.value
    );
    link.value = data.payload.url;
    useAlert(t('WHATSAPP_CALLS.LINK_READY'));
  } catch {
    useAlert(t('WHATSAPP_CALLS.ERROR'));
  } finally {
    acting.value = false;
  }
};
const copyLink = async () => {
  await navigator.clipboard.writeText(link.value);
  useAlert(t('WHATSAPP_CALLS.LINK_COPIED'));
};
const escapeCalendar = value =>
  value
    .replaceAll('\\', '\\\\')
    .replaceAll(',', '\\,')
    .replaceAll(';', '\\;')
    .replaceAll('\n', '\\n');
const calendarDate = date =>
  `${date.toISOString().replaceAll('-', '').replaceAll(':', '').split('.')[0]}Z`;
const downloadEvent = async () => {
  if (!scheduledAt.value || Number(duration.value) < 1) return;
  if (!link.value) await createLink();
  if (!link.value) return;
  const start = new Date(scheduledAt.value);
  const end = new Date(start.getTime() + Number(duration.value) * 60000);
  const event = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Chatwoot Whatsmeow//Calls//PT',
    'BEGIN:VEVENT',
    `UID:${crypto.randomUUID()}@chatwoot`,
    `DTSTAMP:${calendarDate(new Date())}`,
    `DTSTART:${calendarDate(start)}`,
    `DTEND:${calendarDate(end)}`,
    `SUMMARY:${escapeCalendar(t('WHATSAPP_CALLS.VOICE_VIDEO'))}`,
    `DESCRIPTION:${escapeCalendar(link.value)}`,
    `URL:${link.value}`,
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
  const url = URL.createObjectURL(
    new Blob([event], { type: 'text/calendar;charset=utf-8' })
  );
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = 'ligacao-whatsapp.ics';
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  useAlert(t('WHATSAPP_CALLS.CALENDAR_READY'));
};

onMounted(async () => {
  if (!inboxes.value.length) await store.dispatch('inboxes/get');
  selectedInboxId.value = whatsmeowInboxes.value[0]?.id || '';
  try {
    favorites.value = JSON.parse(
      localStorage.getItem(favoriteStorageKey.value) || '[]'
    );
  } catch {
    favorites.value = [];
  }
  loading.value = true;
  await fetchCalls();
  pollTimer = setInterval(fetchCalls, 15000);
});
onBeforeUnmount(() => clearInterval(pollTimer));
</script>

<template>
  <div class="flex h-full min-h-0 w-full bg-n-background">
    <section
      class="flex h-full min-h-0 w-full flex-col border-r border-n-weak bg-n-solid-1 md:max-w-[26rem]"
    >
      <header class="border-b border-n-weak px-5 pb-4 pt-5">
        <div class="flex items-center justify-between">
          <h1 class="mb-0 text-xl font-semibold text-n-slate-12">
            {{ t('WHATSAPP_CALLS.TITLE') }}
          </h1>
          <div class="flex gap-1">
            <button
              v-tooltip.top="t('WHATSAPP_CALLS.DIALPAD')"
              type="button"
              class="rounded-lg p-2 text-n-slate-11 hover:bg-n-alpha-2"
              :aria-label="t('WHATSAPP_CALLS.DIALPAD')"
              @click="selectMode('dial')"
            >
              <Icon icon="i-lucide-grid-3x3" class="size-5" />
            </button>
            <button
              v-tooltip.top="t('WHATSAPP_CALLS.NEW_CALL')"
              type="button"
              class="rounded-lg p-2 text-n-slate-11 hover:bg-n-alpha-2"
              :aria-label="t('WHATSAPP_CALLS.NEW_CALL')"
              @click="selectMode('new')"
            >
              <Icon icon="i-lucide-phone-call" class="size-5" />
            </button>
          </div>
        </div>
        <label
          class="mt-4 flex h-10 items-center gap-3 rounded-full bg-n-alpha-2 px-4 text-n-slate-11 ring-1 ring-transparent transition-shadow focus-within:ring-n-brand/60"
        >
          <Icon icon="i-lucide-search" class="size-4 shrink-0" />
          <input
            v-model="search"
            type="search"
            class="reset-base m-0 min-w-0 flex-1 border-0 bg-transparent p-0 text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10"
            :aria-label="t('WHATSAPP_CALLS.SEARCH')"
            :placeholder="t('WHATSAPP_CALLS.SEARCH')"
          />
        </label>
      </header>
      <div class="min-h-0 flex-1 overflow-y-auto px-3 pb-5">
        <h2
          class="mb-2 mt-5 px-2 text-xs font-semibold uppercase text-n-slate-10"
        >
          {{ t('WHATSAPP_CALLS.FAVORITES') }}
        </h2>
        <div
          v-for="item in filteredFavorites"
          :key="favoriteKey(item)"
          class="group flex items-center gap-3 rounded-xl px-2 py-2 hover:bg-n-alpha-2"
        >
          <Avatar
            :name="item.name"
            :src="item.avatar_url || ''"
            :size="40"
            rounded-full
          />
          <div class="min-w-0 flex-1">
            <p class="mb-0 truncate text-sm font-semibold text-n-slate-12">
              {{ item.name }}
            </p>
            <p class="mb-0 truncate text-xs text-n-slate-11">
              {{ item.inbox_name }} · {{ item.phone_number }}
            </p>
          </div>
          <button
            type="button"
            class="rounded-lg p-1 text-n-slate-11 hover:text-n-brand"
            :aria-label="t('WHATSAPP_CALLS.CALL_CONTACT')"
            @click="startCall(item)"
          >
            <Icon icon="i-lucide-phone" class="size-4" />
          </button>
          <button
            type="button"
            class="rounded-lg p-1 text-n-slate-11 hover:text-n-ruby-9"
            :aria-label="t('WHATSAPP_CALLS.REMOVE_FAVORITE')"
            @click="toggleFavorite(item)"
          >
            <Icon icon="i-lucide-star" class="size-4" />
          </button>
        </div>
        <button
          type="button"
          class="flex w-full items-center gap-3 rounded-xl px-2 py-3 text-left hover:bg-n-alpha-2"
          @click="selectMode('favorite')"
        >
          <span
            class="flex size-10 items-center justify-center rounded-full bg-n-teal-9 text-xl text-white"
          >
            <Icon icon="i-lucide-user-round-plus" />
          </span>
          <span class="text-sm font-medium text-n-slate-12">{{
            t('WHATSAPP_CALLS.ADD_FAVORITE')
          }}</span>
        </button>
        <h2
          class="mb-2 mt-5 px-2 text-xs font-semibold uppercase text-n-slate-10"
        >
          {{ t('WHATSAPP_CALLS.RECENT') }}
        </h2>
        <div v-if="loading" class="flex justify-center py-5">
          <Spinner :size="24" />
        </div>
        <p
          v-else-if="!filteredCalls.length"
          class="px-2 text-sm text-n-slate-11"
        >
          {{ t('WHATSAPP_CALLS.EMPTY_RECENT') }}
        </p>
        <div
          v-for="call in filteredCalls"
          :key="call.id"
          class="group flex items-center gap-3 rounded-xl px-2 py-3 hover:bg-n-alpha-2"
        >
          <Avatar
            :name="call.name"
            :src="call.avatar_url || ''"
            :size="44"
            rounded-full
          />
          <div class="min-w-0 flex-1">
            <p class="mb-0 truncate text-xs text-n-slate-11">
              {{ call.inbox_name }}
            </p>
            <p class="mb-0 truncate text-sm font-semibold text-n-slate-12">
              {{ call.name }}
            </p>
            <p
              class="mb-0 flex items-center gap-1 text-xs"
              :class="
                ['missed', 'declined'].includes(call.status)
                  ? 'text-n-ruby-9'
                  : 'text-n-slate-11'
              "
            >
              <Icon :icon="callIcon(call)" class="size-3" />{{
                callLabel(call)
              }}
              <span v-if="call.duration_seconds"
                >· {{ callDuration(call.duration_seconds) }}</span
              >
            </p>
          </div>
          <div class="flex flex-col items-end gap-1">
            <span class="whitespace-nowrap text-xs text-n-slate-11">{{
              formatTime(call.started_at)
            }}</span>
            <div class="flex gap-1">
              <button
                type="button"
                class="rounded-lg p-1 text-n-slate-11 hover:text-n-brand"
                :aria-label="t('WHATSAPP_CALLS.CALL_CONTACT')"
                @click="startCall(call, call.video)"
              >
                <Icon
                  :icon="call.video ? 'i-lucide-video' : 'i-lucide-phone'"
                  class="size-4"
                />
              </button>
              <button
                type="button"
                class="rounded-lg p-1 text-n-slate-11 hover:text-n-brand"
                :aria-label="
                  isFavorite(call)
                    ? t('WHATSAPP_CALLS.REMOVE_FAVORITE')
                    : t('WHATSAPP_CALLS.ADD_TO_FAVORITES')
                "
                @click="toggleFavorite(call)"
              >
                <Icon
                  :icon="
                    isFavorite(call) ? 'i-lucide-star' : 'i-lucide-star-off'
                  "
                  class="size-4"
                />
              </button>
            </div>
          </div>
        </div>
      </div>
    </section>
    <main
      class="flex min-w-0 flex-1 flex-col items-center justify-center overflow-y-auto px-6 py-8 text-center"
    >
      <template v-if="mode === 'home'">
        <Icon icon="i-lucide-video" class="size-12 text-n-slate-8" />
        <h2 class="mb-0 mt-5 text-2xl font-semibold text-n-slate-12">
          {{ t('WHATSAPP_CALLS.VOICE_VIDEO') }}
        </h2>
        <p class="mt-2 max-w-md text-sm text-n-slate-11">
          {{ t('WHATSAPP_CALLS.INTRO') }}
        </p>
        <div class="mt-10 grid grid-cols-2 gap-5 sm:grid-cols-4">
          <button
            v-for="action in [
              { mode: 'new', icon: 'i-lucide-video', label: 'START' },
              { mode: 'link', icon: 'i-lucide-link', label: 'NEW_LINK' },
              { mode: 'dial', icon: 'i-lucide-grid-3x3', label: 'DIAL' },
              {
                mode: 'schedule',
                icon: 'i-lucide-calendar-days',
                label: 'SCHEDULE',
              },
            ]"
            :key="action.mode"
            type="button"
            class="flex flex-col items-center gap-2 text-xs text-n-slate-12"
            @click="selectMode(action.mode)"
          >
            <span
              class="flex size-14 items-center justify-center rounded-full bg-n-alpha-2 text-2xl hover:bg-n-alpha-3"
            >
              <Icon :icon="action.icon" />
            </span>
            {{ t(`WHATSAPP_CALLS.${action.label}`) }}
          </button>
        </div>
      </template>
      <template v-else>
        <div class="w-full max-w-md text-left">
          <button
            type="button"
            class="mb-5 flex items-center gap-1 text-sm text-n-slate-11 hover:text-n-slate-12"
            @click="selectMode('home')"
          >
            <Icon icon="i-lucide-arrow-left" class="size-4" />{{
              t('WHATSAPP_CALLS.CANCEL')
            }}
          </button>
          <h2 class="mb-4 text-xl font-semibold text-n-slate-12">
            {{
              t(
                `WHATSAPP_CALLS.${{ new: 'NEW_CALL', favorite: 'ADD_FAVORITE', dial: 'DIAL', link: 'NEW_LINK', schedule: 'SCHEDULE' }[mode]}`
              )
            }}
          </h2>
          <label class="mb-4 block text-xs font-medium text-n-slate-11"
            >{{ t('WHATSAPP_CALLS.INBOX') }}
            <select
              v-model="selectedInboxId"
              class="mt-2 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
            >
              <option
                v-for="inbox in whatsmeowInboxes"
                :key="inbox.id"
                :value="inbox.id"
              >
                {{ inbox.name }}
              </option>
            </select>
          </label>
          <p v-if="!whatsmeowInboxes.length" class="text-sm text-n-ruby-9">
            {{ t('WHATSAPP_CALLS.NO_INBOX') }}
          </p>
          <template v-if="mode === 'new' || mode === 'favorite'">
            <label class="block text-xs font-medium text-n-slate-11"
              >{{ t('WHATSAPP_CALLS.CONTACT_SEARCH') }}
              <input
                v-model="contactSearch"
                type="search"
                class="mt-2 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
                :placeholder="t('WHATSAPP_CALLS.SEARCH')"
                @keyup.enter="searchContacts"
              />
            </label>
            <button
              type="button"
              class="mt-3 rounded-lg bg-n-brand px-4 py-2 text-sm text-white disabled:opacity-50"
              :disabled="acting || !contactSearch.trim()"
              @click="searchContacts"
            >
              {{ t('WHATSAPP_CALLS.SEARCH') }}
            </button>
            <p
              v-if="contacts.length === 0 && contactSearch"
              class="mt-4 text-sm text-n-slate-11"
            >
              {{ t('WHATSAPP_CALLS.NO_CONTACTS') }}
            </p>
            <div
              v-for="contact in contacts"
              :key="contact.id"
              class="mt-2 flex items-center gap-3 rounded-lg border border-n-weak p-2"
            >
              <Avatar
                :name="contact.name || contact.phone_number"
                :src="contact.thumbnail || ''"
                :size="36"
                rounded-full
              />
              <div class="min-w-0 flex-1">
                <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
                  {{ contact.name }}
                </p>
                <p class="mb-0 text-xs text-n-slate-11">
                  {{ contact.phone_number }}
                </p>
              </div>
              <button
                v-if="mode === 'favorite'"
                type="button"
                class="rounded-lg p-2 text-n-brand"
                :aria-label="t('WHATSAPP_CALLS.ADD_FAVORITE')"
                @click="toggleFavorite(contactItem(contact))"
              >
                <Icon icon="i-lucide-star" class="size-5" />
              </button>
              <template v-else>
                <button
                  type="button"
                  class="rounded-lg p-2 text-n-brand"
                  :aria-label="t('WHATSAPP_CALLS.VOICE')"
                  @click="startCall(contactItem(contact))"
                >
                  <Icon icon="i-lucide-phone" class="size-5" />
                </button>
                <button
                  type="button"
                  class="rounded-lg p-2 text-n-brand"
                  :aria-label="t('WHATSAPP_CALLS.VIDEO')"
                  @click="startCall(contactItem(contact), true)"
                >
                  <Icon icon="i-lucide-video" class="size-5" />
                </button>
              </template>
            </div>
          </template>
          <template v-if="mode === 'dial'">
            <label class="block text-xs font-medium text-n-slate-11"
              >{{ t('WHATSAPP_CALLS.PHONE') }}
              <input
                v-model="phone"
                type="tel"
                class="mt-2 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-lg text-n-slate-12"
                :placeholder="t('WHATSAPP_CALLS.PHONE_EXAMPLE')"
              />
            </label>
            <div class="mt-5 flex gap-3">
              <button
                type="button"
                class="flex items-center gap-2 rounded-lg bg-n-teal-9 px-4 py-2 text-sm text-white disabled:opacity-50"
                :disabled="acting || !selectedInboxId || !phone.trim()"
                @click="callPhone(false)"
              >
                <Icon icon="i-lucide-phone" class="size-4" />{{
                  t('WHATSAPP_CALLS.VOICE')
                }}
              </button>
              <button
                type="button"
                class="flex items-center gap-2 rounded-lg bg-n-brand px-4 py-2 text-sm text-white disabled:opacity-50"
                :disabled="acting || !selectedInboxId || !phone.trim()"
                @click="callPhone(true)"
              >
                <Icon icon="i-lucide-video" class="size-4" />{{
                  t('WHATSAPP_CALLS.VIDEO')
                }}
              </button>
            </div>
          </template>
          <template v-if="mode === 'link' || mode === 'schedule'">
            <p class="mb-4 text-sm text-n-slate-11">
              {{
                t(
                  mode === 'schedule'
                    ? 'WHATSAPP_CALLS.SCHEDULE_HELP'
                    : 'WHATSAPP_CALLS.LINK_HELP'
                )
              }}
            </p>
            <label class="mb-4 flex items-center gap-2 text-sm text-n-slate-12"
              ><input v-model="video" type="checkbox" />{{
                t('WHATSAPP_CALLS.VIDEO')
              }}</label
            >
            <template v-if="mode === 'schedule'">
              <label class="mb-4 block text-xs font-medium text-n-slate-11"
                >{{ t('WHATSAPP_CALLS.DATE_TIME')
                }}<input
                  v-model="scheduledAt"
                  type="datetime-local"
                  class="mt-2 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
              /></label>
              <label class="mb-4 block text-xs font-medium text-n-slate-11"
                >{{ t('WHATSAPP_CALLS.DURATION')
                }}<input
                  v-model="duration"
                  type="number"
                  min="1"
                  max="1440"
                  class="mt-2 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
              /></label>
            </template>
            <button
              type="button"
              class="rounded-lg bg-n-brand px-4 py-2 text-sm text-white disabled:opacity-50"
              :disabled="
                acting ||
                !selectedInboxId ||
                (mode === 'schedule' && !scheduledAt)
              "
              @click="mode === 'schedule' ? downloadEvent() : createLink()"
            >
              {{
                t(
                  mode === 'schedule'
                    ? 'WHATSAPP_CALLS.DOWNLOAD_EVENT'
                    : 'WHATSAPP_CALLS.CREATE_LINK'
                )
              }}
            </button>
            <div
              v-if="link"
              class="mt-5 flex items-center gap-2 rounded-lg border border-n-weak p-3"
            >
              <span class="min-w-0 flex-1 truncate text-sm text-n-slate-12">{{
                link
              }}</span
              ><button
                type="button"
                class="text-n-brand"
                :aria-label="t('WHATSAPP_CALLS.COPY_LINK')"
                @click="copyLink"
              >
                <Icon icon="i-lucide-copy" class="size-5" />
              </button>
            </div>
          </template>
        </div>
      </template>
    </main>
  </div>
</template>
