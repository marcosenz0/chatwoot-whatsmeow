<script setup>
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import InboxesAPI from 'dashboard/api/inboxes';
import {
  whatsmeowConversationPath,
  whatsmeowDirectConversationPayload,
} from 'dashboard/helper/whatsmeowConversationHelper';
import { useMessageContext } from '../provider.js';
import BaseBubble from './Base.vue';
import MessageMeta from '../MessageMeta.vue';
import Avatar from 'next/avatar/Avatar.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';

import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';

const { attachments, inboxId } = useMessageContext();
const $store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const showDetails = ref(false);
const isSavingContact = ref(false);
const isOpeningConversation = ref(false);
const savedContactId = ref(null);

const valueFrom = (source, keys) => {
  if (!source) return '';
  const key = keys.find(
    item => source[item] !== undefined && source[item] !== null
  );
  return key ? source[key] : '';
};

const compactValue = value => {
  if (Array.isArray(value)) return value.filter(Boolean).join(', ');
  return String(value || '').trim();
};

const digitsOnly = value => compactValue(value).replace(/\D/g, '');

const normalizePhoneNumber = value => {
  const digits = digitsOnly(value);
  return digits.length >= 8 ? `+${digits}` : compactValue(value);
};

const vcardLines = value => {
  const lines = [];
  compactValue(value)
    .replace(/\r\n/g, '\n')
    .split('\n')
    .forEach(line => {
      if (!line) return;
      if (/^[ \t]/.test(line) && lines.length) {
        lines[lines.length - 1] += line.trim();
      } else {
        lines.push(line.trim());
      }
    });
  return lines;
};

const vcardField = (vcard, field) => {
  const prefix = field.toUpperCase();
  const line = vcardLines(vcard).find(item =>
    item.toUpperCase().startsWith(prefix)
  );
  if (!line) return '';
  return compactValue(line.slice(line.indexOf(':') + 1));
};

const vcardPhone = vcard => {
  const line = vcardLines(vcard).find(item =>
    item.toUpperCase().startsWith('TEL')
  );
  if (!line) return '';

  const waid = line.match(/waid=([^;:]+)/i)?.[1];
  const value = line.slice(line.indexOf(':') + 1);
  return normalizePhoneNumber(waid || value);
};

const arrayValue = value => (Array.isArray(value) ? value : []);

const externalUrl = value => {
  const url = compactValue(value);
  if (!url) return '';
  return /^https?:\/\//i.test(url) ? url : `https://${url}`;
};

const attachment = computed(() => attachments.value[0] || {});
const meta = computed(() => attachment.value.meta || {});
const vcard = computed(() => compactValue(valueFrom(meta.value, ['vcard'])));
const businessProfile = computed(
  () => valueFrom(meta.value, ['businessProfile', 'business_profile']) || {}
);
const profileOptions = computed(
  () =>
    valueFrom(businessProfile.value, ['profileOptions', 'profile_options']) ||
    {}
);

const rawPhoneNumber = computed(() =>
  digitsOnly(
    attachment.value.fallbackTitle ||
      valueFrom(meta.value, [
        'phoneNumber',
        'phone_number',
        'whatsappId',
        'whatsapp_id',
        'waid',
        'phone',
      ]) ||
      vcardPhone(vcard.value) ||
      valueFrom(businessProfile.value, ['jid'])
  )
);

const phoneNumber = computed(() => {
  if (!rawPhoneNumber.value) return '';
  return `+${rawPhoneNumber.value}`;
});

const fullName = computed(() =>
  compactValue(
    valueFrom(meta.value, ['displayName', 'display_name']) ||
      valueFrom(meta.value, ['fullName', 'full_name']) ||
      vcardField(vcard.value, 'FN') ||
      `${valueFrom(meta.value, ['firstName', 'first_name'])} ${valueFrom(meta.value, ['lastName', 'last_name'])}`
  )
);

const contactName = computed(
  () =>
    fullName.value ||
    compactValue(valueFrom(meta.value, ['organization'])) ||
    phoneNumber.value ||
    t('CONVERSATION.WHATSMEOW_CONTACT.UNKNOWN_CONTACT')
);

const contactJid = computed(
  () =>
    compactValue(valueFrom(meta.value, ['jid'])) ||
    compactValue(valueFrom(businessProfile.value, ['jid'])) ||
    (rawPhoneNumber.value ? `${rawPhoneNumber.value}@s.whatsapp.net` : '')
);

const avatarUrl = computed(() =>
  compactValue(
    valueFrom(meta.value, [
      'profilePictureUrl',
      'profile_picture_url',
      'avatarUrl',
      'avatar_url',
    ])
  )
);

const organization = computed(() =>
  compactValue(
    valueFrom(meta.value, ['organization']) ||
      valueFrom(businessProfile.value, ['businessName', 'business_name']) ||
      vcardField(vcard.value, 'ORG')
  )
);

const category = computed(() =>
  compactValue(
    valueFrom(meta.value, ['category']) ||
      valueFrom(businessProfile.value, ['category']) ||
      arrayValue(valueFrom(businessProfile.value, ['categories']))
        .map(item => compactValue(item.name || item.label))
        .filter(Boolean)
  )
);

const website = computed(() =>
  compactValue(
    valueFrom(meta.value, ['website']) ||
      valueFrom(businessProfile.value, ['website']) ||
      valueFrom(profileOptions.value, [
        'website',
        'websiteUrl',
        'website_url',
        'profileWebsite',
        'profile_website',
      ])
  )
);

const websiteHref = computed(() => externalUrl(website.value));

const email = computed(() =>
  compactValue(
    valueFrom(meta.value, ['email']) ||
      valueFrom(businessProfile.value, ['email']) ||
      vcardField(vcard.value, 'EMAIL')
  )
);

const businessHours = computed(() =>
  compactValue(
    valueFrom(businessProfile.value, [
      'businessHoursDisplayText',
      'business_hours_display_text',
    ])
  )
);

const address = computed(() =>
  compactValue(valueFrom(businessProfile.value, ['address']))
);

const note = computed(() =>
  compactValue(
    valueFrom(meta.value, ['note']) || vcardField(vcard.value, 'NOTE')
  )
);

const coverUrl = computed(() =>
  compactValue(
    valueFrom(businessProfile.value, [
      'coverPhotoUrl',
      'cover_photo_url',
      'coverUrl',
      'cover_url',
      'headerImageUrl',
      'header_image_url',
      'profileCoverPhoto',
      'profile_cover_photo',
    ]) ||
      valueFrom(profileOptions.value, [
        'coverPhotoUrl',
        'cover_photo_url',
        'cover_url',
      ])
  )
);

const isContactSaved = computed(() => !!savedContactId.value);

const hasBusinessDetails = computed(
  () =>
    !!(
      category.value ||
      website.value ||
      email.value ||
      address.value ||
      businessHours.value ||
      note.value ||
      organization.value
    )
);

const headline = computed(() => category.value || organization.value);

const subtitle = computed(
  () =>
    (hasBusinessDetails.value &&
      t('CONVERSATION.WHATSMEOW_CONTACT.BUSINESS_ACCOUNT')) ||
    t('CONVERSATION.WHATSMEOW_CONTACT.WHATSAPP_CONTACT')
);

const detailsRows = computed(() =>
  [
    {
      icon: 'i-lucide-phone',
      label: t('CONVERSATION.WHATSMEOW_CONTACT.PHONE'),
      value: phoneNumber.value,
      href: phoneNumber.value ? `tel:${phoneNumber.value}` : '',
    },
    {
      icon: 'i-lucide-briefcase-business',
      label: t('CONVERSATION.WHATSMEOW_CONTACT.COMPANY'),
      value: organization.value,
    },
    {
      icon: 'i-lucide-store',
      label: t('CONVERSATION.WHATSMEOW_CONTACT.CATEGORY'),
      value: category.value,
    },
    {
      icon: 'i-lucide-clock',
      label: t('CONVERSATION.WHATSMEOW_CONTACT.HOURS'),
      value: businessHours.value,
    },
    {
      icon: 'i-lucide-globe',
      label: t('CONVERSATION.WHATSMEOW_CONTACT.WEBSITE'),
      value: website.value,
      href: websiteHref.value,
    },
    {
      icon: 'i-lucide-mail',
      label: t('CONVERSATION.WHATSMEOW_CONTACT.EMAIL'),
      value: email.value,
      href: email.value ? `mailto:${email.value}` : '',
    },
    {
      icon: 'i-lucide-map-pin',
      label: t('CONVERSATION.WHATSMEOW_CONTACT.ADDRESS'),
      value: address.value,
    },
    {
      icon: 'i-lucide-message-square-text',
      label: t('CONVERSATION.WHATSMEOW_CONTACT.NOTE'),
      value: note.value,
    },
  ].filter(row => row.value)
);

async function filterContact(attributeKey, searchCandidate) {
  const query = {
    attribute_key: attributeKey,
    filter_operator: 'equal_to',
    values: [searchCandidate],
    attribute_model: 'standard',
    custom_attribute_type: '',
  };

  const queryPayload = { payload: [query] };
  const contacts = await $store.dispatch('contacts/filter', {
    queryPayload,
    resetState: false,
  });
  return contacts.shift();
}

async function findExistingContact() {
  if (phoneNumber.value) {
    const contact = await filterContact('phone_number', phoneNumber.value);
    if (contact) return contact;
  }

  if (email.value) {
    return filterContact('email', email.value);
  }

  return null;
}

function getContactObject() {
  return {
    name: contactName.value,
    phone_number: phoneNumber.value,
    email: email.value,
    additional_attributes: {
      company_name: organization.value,
      website: website.value,
      description: note.value,
      whatsapp_business_category: category.value,
      whatsapp_jid: contactJid.value,
      social_profiles: {},
    },
  };
}

async function addContact() {
  if (
    (!contactName.value && !phoneNumber.value && !email.value) ||
    isSavingContact.value
  )
    return;

  isSavingContact.value = true;
  try {
    let contact = await findExistingContact();
    if (!contact) {
      contact = await $store.dispatch('contacts/create', getContactObject());
    }
    savedContactId.value = contact.id;
    useAlert(t('CONTACT_FORM.SUCCESS_MESSAGE'));
  } catch (error) {
    if (error instanceof DuplicateContactException) {
      if (error.data.includes('phone_number')) {
        useAlert(t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
      }
    } else if (error instanceof ExceptionWithMessage) {
      useAlert(error.data);
    } else {
      useAlert(t('CONTACT_FORM.ERROR_MESSAGE'));
    }
  } finally {
    isSavingContact.value = false;
  }
}

async function openPrivateConversation() {
  if (
    (!phoneNumber.value && !contactJid.value) ||
    isOpeningConversation.value
  ) {
    return;
  }

  isOpeningConversation.value = true;
  try {
    const { data } = await InboxesAPI.createWhatsmeowDirectConversation(
      inboxId.value,
      whatsmeowDirectConversationPayload({
        jid: contactJid.value,
        phoneNumber: phoneNumber.value,
        name: contactName.value,
        profilePictureUrl: avatarUrl.value,
      })
    );
    const conversationId =
      data.conversation_id ||
      data.display_id ||
      data.id ||
      data.payload?.conversation_id ||
      data.payload?.display_id ||
      data.payload?.id;
    if (!conversationId) throw new Error('Missing conversation id');

    await router.push({
      path: whatsmeowConversationPath({
        route,
        inboxId: inboxId.value,
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
}
</script>

<template>
  <BaseBubble
    hide-meta
    class="w-80 max-w-[min(20rem,calc(100vw-5rem))] overflow-hidden"
  >
    <div class="flex items-start gap-3 p-3">
      <Avatar :name="contactName" :src="avatarUrl" :size="40" />
      <div class="min-w-0 flex-1">
        <p class="m-0 truncate text-sm font-semibold text-n-slate-12">
          {{ contactName }}
        </p>
        <p class="m-0 truncate text-xs text-n-slate-11">
          {{ subtitle }}
        </p>
        <p v-if="headline" class="m-0 mt-1 truncate text-sm text-n-slate-12">
          {{ headline }}
        </p>
        <p v-if="phoneNumber" class="m-0 mt-1 truncate text-sm text-n-slate-12">
          {{ phoneNumber }}
        </p>
      </div>
    </div>

    <div v-if="website || note" class="border-t border-n-weak px-3 py-2">
      <a
        v-if="website"
        :href="websiteHref"
        target="_blank"
        rel="noreferrer noopener nofollow"
        class="block truncate text-sm font-medium text-n-blue-11 hover:underline"
      >
        {{ website }}
      </a>
      <p v-if="note" class="m-0 line-clamp-2 text-xs text-n-slate-11">
        {{ note }}
      </p>
    </div>

    <div class="grid border-t border-n-weak">
      <button
        type="button"
        class="flex items-center justify-center gap-2 px-3 py-2 text-sm font-semibold text-n-teal-11 hover:bg-n-alpha-2"
        :disabled="isOpeningConversation"
        @click.stop="openPrivateConversation"
      >
        <Icon icon="i-lucide-message-circle" class="size-4" />
        <span>{{ $t('CONVERSATION.WHATSMEOW_GROUP.OPEN_PRIVATE_CHAT') }}</span>
      </button>
      <button
        type="button"
        class="flex items-center justify-center gap-2 border-t border-n-weak px-3 py-2 text-sm font-semibold text-n-teal-11 hover:bg-n-alpha-2"
        @click.stop="showDetails = true"
      >
        <Icon icon="i-lucide-building-2" class="size-4" />
        <span>{{ $t('CONVERSATION.WHATSMEOW_CONTACT.VIEW_BUSINESS') }}</span>
      </button>
      <button
        type="button"
        class="flex items-center justify-center gap-2 border-t border-n-weak px-3 py-2 text-sm font-semibold text-n-teal-11 hover:bg-n-alpha-2"
        :disabled="isContactSaved || isSavingContact"
        @click.stop="addContact"
      >
        <Icon
          :icon="isContactSaved ? 'i-lucide-check' : 'i-lucide-user-plus'"
          class="size-4"
        />
        <span>
          {{
            isContactSaved
              ? $t('CONVERSATION.WHATSMEOW_CONTACT.CONTACT_SAVED')
              : $t('CONVERSATION.SAVE_CONTACT')
          }}
        </span>
      </button>
    </div>

    <div class="flex px-3 pb-2 pt-1">
      <MessageMeta class="text-n-slate-11" />
    </div>

    <div
      v-if="showDetails"
      class="fixed inset-0 z-[100] flex items-center justify-center bg-modal-backdrop-light p-4 dark:bg-modal-backdrop-dark"
      @click.self="showDetails = false"
    >
      <section
        class="max-h-[88vh] w-full max-w-lg overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-xl"
      >
        <header class="relative border-b border-n-weak">
          <div class="h-28 bg-n-slate-5" :class="{ 'bg-n-teal-5': !coverUrl }">
            <img
              v-if="coverUrl"
              :src="coverUrl"
              :alt="contactName"
              class="size-full object-cover"
            />
          </div>
          <NextButton
            icon="i-lucide-x"
            slate
            ghost
            sm
            class="absolute right-3 top-3 bg-n-solid-1/80"
            @click="showDetails = false"
          />
          <div class="-mt-9 flex flex-col items-center px-4 pb-4 text-center">
            <Avatar
              :name="contactName"
              :src="avatarUrl"
              :size="72"
              rounded-full
            />
            <h3
              class="m-0 mt-3 max-w-full truncate text-lg font-semibold text-n-slate-12"
            >
              {{ contactName }}
            </h3>
            <p v-if="organization" class="m-0 text-sm text-n-slate-12">
              {{ organization }}
            </p>
            <p class="m-0 text-sm text-n-slate-11">
              {{ subtitle }}
            </p>
          </div>
        </header>

        <div class="max-h-[58vh] overflow-y-auto p-4">
          <div class="mb-4 grid grid-cols-2 gap-2">
            <button
              type="button"
              class="flex items-center justify-center gap-2 rounded-lg border border-n-weak px-3 py-3 text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-2"
              :disabled="isOpeningConversation"
              @click.stop="openPrivateConversation"
            >
              <Icon icon="i-lucide-message-circle" class="size-4" />
              <span>{{
                $t('CONVERSATION.WHATSMEOW_GROUP.OPEN_PRIVATE_CHAT')
              }}</span>
            </button>
            <button
              type="button"
              class="flex items-center justify-center gap-2 rounded-lg border border-n-weak px-3 py-3 text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-60"
              :disabled="isContactSaved || isSavingContact"
              @click.stop="addContact"
            >
              <Icon
                :icon="isContactSaved ? 'i-lucide-check' : 'i-lucide-user-plus'"
                class="size-4"
              />
              <span>
                {{
                  isContactSaved
                    ? $t('CONVERSATION.WHATSMEOW_CONTACT.CONTACT_SAVED')
                    : $t('CONVERSATION.SAVE_CONTACT')
                }}
              </span>
            </button>
          </div>

          <div v-if="detailsRows.length" class="grid gap-3">
            <div
              v-for="row in detailsRows"
              :key="row.label"
              class="flex items-start gap-3 rounded-lg bg-n-alpha-1 p-3"
            >
              <Icon
                :icon="row.icon"
                class="mt-0.5 size-4 shrink-0 text-n-slate-10"
              />
              <div class="min-w-0">
                <p class="m-0 text-xs font-medium text-n-slate-10">
                  {{ row.label }}
                </p>
                <a
                  v-if="row.href"
                  :href="row.href"
                  target="_blank"
                  rel="noreferrer noopener nofollow"
                  class="break-words text-sm font-medium text-n-blue-11 hover:underline"
                >
                  {{ row.value }}
                </a>
                <p v-else class="m-0 break-words text-sm text-n-slate-12">
                  {{ row.value }}
                </p>
              </div>
            </div>
          </div>
          <div
            v-else
            class="rounded-lg border border-dashed border-n-weak p-4 text-sm text-n-slate-11"
          >
            {{ $t('CONVERSATION.WHATSMEOW_CONTACT.NO_BUSINESS_DETAILS') }}
          </div>
        </div>

        <footer
          class="flex flex-wrap justify-end gap-2 border-t border-n-weak p-4"
        >
          <NextButton
            :label="$t('CONVERSATION.WHATSMEOW_GROUP.OPEN_PRIVATE_CHAT')"
            icon="i-lucide-message-circle"
            slate
            faded
            :is-loading="isOpeningConversation"
            @click="openPrivateConversation"
          />
          <NextButton
            :label="
              isContactSaved
                ? $t('CONVERSATION.WHATSMEOW_CONTACT.CONTACT_SAVED')
                : $t('CONVERSATION.SAVE_CONTACT')
            "
            :icon="isContactSaved ? 'i-lucide-check' : 'i-lucide-user-plus'"
            :disabled="isContactSaved"
            :is-loading="isSavingContact"
            @click="addContact"
          />
        </footer>
      </section>
    </div>
  </BaseBubble>
</template>
