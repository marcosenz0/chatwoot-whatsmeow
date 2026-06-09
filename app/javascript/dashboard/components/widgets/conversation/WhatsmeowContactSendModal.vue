<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ContactAPI from 'dashboard/api/contacts';
import Avatar from 'next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  isOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'send']);
const { t } = useI18n();

const query = ref('');
const contacts = ref([]);
const isFetching = ref(false);
const mode = ref('list');
const requestId = ref(0);
let searchTimer = null;

const emptyForm = () => ({
  displayName: '',
  phoneNumber: '',
  organization: '',
  category: '',
  website: '',
  email: '',
  note: '',
});

const form = reactive(emptyForm());

const resetForm = () => {
  Object.assign(form, emptyForm());
};

const resetModal = () => {
  query.value = '';
  contacts.value = [];
  mode.value = 'list';
  resetForm();
};

const compactValue = value => String(value || '').trim();

const normalizePhoneNumber = value => {
  const digits = compactValue(value).replace(/\D/g, '');
  return digits ? `+${digits}` : '';
};

const additionalAttributes = contact =>
  contact.additional_attributes || contact.additionalAttributes || {};

const contactName = contact =>
  compactValue(contact.name || contact.display_name || contact.displayName) ||
  t('CONVERSATION.WHATSMEOW_CONTACT.UNKNOWN_CONTACT');

const contactPhone = contact =>
  normalizePhoneNumber(contact.phone_number || contact.phoneNumber);

const contactCompany = contact =>
  compactValue(
    additionalAttributes(contact).company_name ||
      additionalAttributes(contact).companyName ||
      contact.company?.name
  );

const contactWebsite = contact =>
  compactValue(
    additionalAttributes(contact).website ||
      additionalAttributes(contact).profile_website ||
      additionalAttributes(contact).profileWebsite
  );

const contactNote = contact =>
  compactValue(
    additionalAttributes(contact).description ||
      additionalAttributes(contact).bio ||
      contact.description
  );

const contactAvatar = contact =>
  compactValue(contact.thumbnail || contact.avatar_url || contact.avatarUrl);

const contactSubtitle = contact => {
  const parts = [
    contactPhone(contact),
    compactValue(contact.email),
    contactCompany(contact),
  ].filter(Boolean);
  return parts.join(' · ');
};

const canSendCustom = computed(
  () => !!form.displayName.trim() && !!normalizePhoneNumber(form.phoneNumber)
);

const hasContacts = computed(() => contacts.value.length > 0);

const fetchContacts = async () => {
  const currentRequestId = requestId.value + 1;
  requestId.value = currentRequestId;
  isFetching.value = true;

  try {
    const response = query.value.trim()
      ? await ContactAPI.search(query.value.trim(), 1, 'name')
      : await ContactAPI.get(1, 'name');

    if (currentRequestId !== requestId.value) return;
    contacts.value = response.data?.payload || [];
  } catch {
    if (currentRequestId === requestId.value) contacts.value = [];
  } finally {
    if (currentRequestId === requestId.value) isFetching.value = false;
  }
};

watch(
  () => props.isOpen,
  value => {
    if (value) {
      resetModal();
      fetchContacts();
    } else {
      resetModal();
    }
  }
);

watch(query, () => {
  if (!props.isOpen || mode.value !== 'list') return;
  clearTimeout(searchTimer);
  searchTimer = setTimeout(fetchContacts, 250);
});

const contactPayload = contact => ({
  display_name: contactName(contact),
  full_name: contactName(contact),
  phone_number: contactPhone(contact),
  organization: contactCompany(contact),
  website: contactWebsite(contact),
  email: compactValue(contact.email),
  note: contactNote(contact),
  avatar_url: contactAvatar(contact),
});

const sendExistingContact = contact => {
  const payload = contactPayload(contact);
  if (!payload.phone_number) return;
  emit('send', payload);
};

const submitCustomContact = () => {
  if (!canSendCustom.value) return;

  emit('send', {
    display_name: form.displayName.trim(),
    full_name: form.displayName.trim(),
    phone_number: normalizePhoneNumber(form.phoneNumber),
    organization: form.organization.trim(),
    category: form.category.trim(),
    website: form.website.trim(),
    email: form.email.trim(),
    note: form.note.trim(),
  });
};
</script>

<template>
  <div class="contents">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-[100] flex items-center justify-center bg-modal-backdrop-light p-4 dark:bg-modal-backdrop-dark"
      @click.self="$emit('close')"
    >
      <section
        class="flex max-h-[86vh] w-full max-w-lg flex-col overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-xl"
      >
        <header
          class="flex items-center justify-between gap-3 border-b border-n-weak p-4"
        >
          <div class="flex min-w-0 items-center gap-3">
            <button
              v-if="mode === 'custom'"
              type="button"
              class="grid size-9 shrink-0 place-content-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              @click="mode = 'list'"
            >
              <Icon icon="i-lucide-arrow-left" class="size-4" />
            </button>
            <div
              v-else
              class="grid size-10 shrink-0 place-content-center rounded-lg bg-n-teal-9/15 text-n-teal-11"
            >
              <Icon icon="i-lucide-contact" class="size-5" />
            </div>
            <div class="min-w-0">
              <h3 class="m-0 truncate text-base font-semibold text-n-slate-12">
                {{ t('CONVERSATION.WHATSMEOW_CONTACT.SEND_CONTACT') }}
              </h3>
              <p class="m-0 truncate text-sm text-n-slate-11">
                {{
                  mode === 'custom'
                    ? t('CONVERSATION.WHATSMEOW_CONTACT.CUSTOM_CONTACT_HINT')
                    : t('CONVERSATION.WHATSMEOW_CONTACT.SELECT_CONTACT_HINT')
                }}
              </p>
            </div>
          </div>
          <NextButton
            icon="i-lucide-x"
            slate
            ghost
            sm
            @click="$emit('close')"
          />
        </header>

        <template v-if="mode === 'list'">
          <div class="border-b border-n-weak p-4">
            <label
              class="flex h-10 items-center gap-2 rounded-lg border border-n-weak bg-n-alpha-1 px-3"
            >
              <Icon icon="i-lucide-search" class="size-4 text-n-slate-10" />
              <input
                v-model="query"
                class="reset-base h-full min-w-0 flex-1 bg-transparent text-sm text-n-slate-12 outline-none"
                type="search"
                autocomplete="off"
                :placeholder="
                  t('CONVERSATION.WHATSMEOW_CONTACT.SEARCH_CONTACTS')
                "
              />
            </label>
          </div>

          <div class="min-h-64 flex-1 overflow-y-auto p-2">
            <div
              v-if="isFetching"
              class="flex h-40 items-center justify-center text-sm text-n-slate-11"
            >
              {{ t('CONVERSATION.WHATSMEOW_CONTACT.LOADING_CONTACTS') }}
            </div>

            <div
              v-else-if="!hasContacts"
              class="flex h-40 flex-col items-center justify-center gap-2 text-center text-sm text-n-slate-11"
            >
              <Icon icon="i-lucide-contact" class="size-8" />
              <p class="m-0">
                {{ t('CONVERSATION.WHATSMEOW_CONTACT.NO_CONTACTS_FOUND') }}
              </p>
            </div>

            <template v-else>
              <button
                v-for="contact in contacts"
                :key="contact.id"
                type="button"
                class="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                :disabled="!contactPhone(contact)"
                @click="sendExistingContact(contact)"
              >
                <Avatar
                  :name="contactName(contact)"
                  :src="contactAvatar(contact)"
                  :size="36"
                />
                <div class="min-w-0 flex-1">
                  <p class="m-0 truncate text-sm font-medium text-n-slate-12">
                    {{ contactName(contact) }}
                  </p>
                  <p class="m-0 truncate text-xs text-n-slate-11">
                    {{
                      contactSubtitle(contact) ||
                      t('CONVERSATION.WHATSMEOW_CONTACT.NO_PHONE')
                    }}
                  </p>
                </div>
                <Icon icon="i-lucide-send" class="size-4 text-n-slate-10" />
              </button>
            </template>
          </div>

          <footer
            class="flex items-center justify-between gap-2 border-t border-n-weak p-4"
          >
            <NextButton
              :label="t('CONVERSATION.WHATSMEOW_CONTACT.CUSTOM_CONTACT')"
              icon="i-lucide-pencil-line"
              slate
              faded
              @click="mode = 'custom'"
            />
            <NextButton
              :label="t('CONVERSATION.WHATSMEOW_CONTACT.CANCEL')"
              slate
              ghost
              @click="$emit('close')"
            />
          </footer>
        </template>

        <form
          v-else
          class="overflow-y-auto"
          @submit.prevent="submitCustomContact"
        >
          <div class="grid gap-4 p-4">
            <label class="grid gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('CONVERSATION.WHATSMEOW_CONTACT.NAME') }}
              </span>
              <input
                v-model="form.displayName"
                class="reset-base h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                type="text"
                autocomplete="off"
              />
            </label>

            <label class="grid gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('CONVERSATION.WHATSMEOW_CONTACT.PHONE') }}
              </span>
              <input
                v-model="form.phoneNumber"
                class="reset-base h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                type="tel"
                autocomplete="off"
              />
            </label>

            <div class="grid gap-4 sm:grid-cols-2">
              <label class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CONVERSATION.WHATSMEOW_CONTACT.COMPANY') }}
                </span>
                <input
                  v-model="form.organization"
                  class="reset-base h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                  type="text"
                  autocomplete="off"
                />
              </label>

              <label class="grid gap-1">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('CONVERSATION.WHATSMEOW_CONTACT.CATEGORY') }}
                </span>
                <input
                  v-model="form.category"
                  class="reset-base h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                  type="text"
                  autocomplete="off"
                />
              </label>
            </div>

            <label class="grid gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('CONVERSATION.WHATSMEOW_CONTACT.WEBSITE') }}
              </span>
              <input
                v-model="form.website"
                class="reset-base h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                type="url"
                autocomplete="off"
              />
            </label>

            <label class="grid gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('CONVERSATION.WHATSMEOW_CONTACT.EMAIL') }}
              </span>
              <input
                v-model="form.email"
                class="reset-base h-10 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                type="email"
                autocomplete="off"
              />
            </label>

            <label class="grid gap-1">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('CONVERSATION.WHATSMEOW_CONTACT.NOTE') }}
              </span>
              <textarea
                v-model="form.note"
                class="reset-base min-h-20 resize-y rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
              />
            </label>
          </div>

          <footer class="flex justify-end gap-2 border-t border-n-weak p-4">
            <NextButton
              :label="t('CONVERSATION.WHATSMEOW_CONTACT.CANCEL')"
              slate
              faded
              @click="mode = 'list'"
            />
            <NextButton
              type="submit"
              icon="i-lucide-send"
              :label="t('CONVERSATION.WHATSMEOW_CONTACT.SEND_CONTACT')"
              :disabled="!canSendCustom"
            />
          </footer>
        </form>
      </section>
    </div>
  </div>
</template>
