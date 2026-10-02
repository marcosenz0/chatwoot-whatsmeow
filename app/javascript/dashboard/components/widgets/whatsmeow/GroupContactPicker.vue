<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { watchDebounced } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import GroupsAPI from 'dashboard/api/whatsmeowGroups';
import InboxesAPI from 'dashboard/api/inboxes';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'next/button/Button.vue';
import Input from 'next/input/Input.vue';
import Spinner from 'next/spinner/Spinner.vue';

const props = defineProps({
  inboxId: { type: Number, required: true },
  modelValue: { type: Array, default: () => [] },
  excluded: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const request = useAbortableRequest();
const query = ref('');
const contacts = ref([]);
const more = ref(false);
const error = ref('');
const checking = ref(false);
const visible = computed(() =>
  contacts.value.filter(c => !c.is_self && !props.excluded.includes(c.jid))
);
const canLookup = computed(() =>
  /^\+?[1-9]\d{9,14}$/.test(query.value.replace(/[\s()-]/g, ''))
);
const selected = jid => props.modelValue.some(c => c.jid === jid);
function toggle(contact) {
  emit(
    'update:modelValue',
    selected(contact.jid)
      ? props.modelValue.filter(c => c.jid !== contact.jid)
      : [...props.modelValue, contact]
  );
}
async function load(append = false) {
  error.value = '';
  try {
    const response = await request.run(signal =>
      GroupsAPI.contacts(
        props.inboxId,
        { q: query.value, offset: append ? contacts.value.length : 0 },
        { signal }
      )
    );
    if (!response) return;
    contacts.value = append
      ? [...contacts.value, ...response.data.contacts]
      : response.data.contacts;
    more.value = response.data.has_more;
  } catch (e) {
    error.value = e.response?.data?.message || t('WHATSMEOW_UI.LOAD_ERROR');
  }
}
async function lookup() {
  checking.value = true;
  try {
    const { data } = await InboxesAPI.checkWhatsmeowNumber(
      props.inboxId,
      query.value
    );
    if (!data.is_on_whatsapp)
      throw new Error(t('WHATSMEOW_UI.NUMBER_UNAVAILABLE'));
    const contact = {
      jid: data.jid,
      name: query.value,
      phone_number: query.value,
    };
    if (!props.excluded.includes(contact.jid) && !selected(contact.jid))
      toggle(contact);
  } catch (e) {
    error.value = e.response?.data?.message || e.message;
  }
  checking.value = false;
}
watchDebounced(query, () => load(), { debounce: 300 });
watch(
  () => props.inboxId,
  () => {
    emit('update:modelValue', []);
    contacts.value = [];
    load();
  }
);
onMounted(load);
</script>

<template>
  <div class="flex min-h-0 flex-col gap-3">
    <div
      v-if="modelValue.length"
      class="flex max-h-24 flex-wrap gap-2 overflow-auto"
    >
      <button
        v-for="contact in modelValue"
        :key="contact.jid"
        type="button"
        class="flex items-center gap-2 rounded-full bg-n-alpha-2 px-2 py-1 text-xs"
        @click="toggle(contact)"
      >
        <Avatar
          :name="contact.name"
          :src="contact.profile_picture_url"
          :size="20"
          hide-offline-status
        />{{ contact.name }}<span class="i-lucide-x size-3" />
      </button>
    </div>
    <Input
      v-model="query"
      :placeholder="$t('WHATSMEOW_UI.SEARCH_CONTACTS')"
      size="sm"
    />
    <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
      {{ error }}
    </p>
    <div class="min-h-0 max-h-80 overflow-y-auto">
      <div
        v-if="request.isPending.value && !contacts.length"
        class="flex justify-center p-4"
      >
        <Spinner />
      </div>
      <button
        v-for="contact in visible"
        :key="contact.jid"
        type="button"
        class="flex w-full items-center gap-3 rounded-lg px-2 py-3 text-start hover:bg-n-alpha-2"
        :aria-pressed="selected(contact.jid)"
        @click="toggle(contact)"
      >
        <span
          :class="
            selected(contact.jid)
              ? 'i-lucide-square-check text-n-brand'
              : 'i-lucide-square text-n-slate-10'
          "
          class="size-5 shrink-0"
        />
        <Avatar
          :name="contact.name"
          :src="contact.profile_picture_url"
          :size="36"
          hide-offline-status
        />
        <span class="min-w-0 flex-1">
          <span class="block truncate text-sm font-medium">
            {{ contact.name }}
          </span>
          <span class="block text-xs text-n-slate-11">
            {{ contact.phone_number }}
          </span>
        </span>
      </button>
      <p
        v-if="!request.isPending.value && !visible.length"
        class="p-3 text-sm text-n-slate-11"
      >
        {{ $t('WHATSMEOW_UI.NO_CONTACTS') }}
      </p>
      <Button
        v-if="more"
        type="button"
        :label="$t('WHATSMEOW_UI.LOAD_MORE')"
        faded
        slate
        class="w-full"
        @click="load(true)"
      />
    </div>
    <Button
      v-if="canLookup"
      type="button"
      :label="$t('WHATSMEOW_UI.ADD_NUMBER')"
      icon="i-lucide-user-plus"
      faded
      :is-loading="checking"
      @click="lookup"
    />
  </div>
</template>
