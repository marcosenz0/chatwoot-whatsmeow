<script setup>
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
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

watch(
  () => props.isOpen,
  value => {
    if (!value) resetForm();
  }
);

const normalizedPhoneNumber = computed(() => {
  const digits = form.phoneNumber.replace(/\D/g, '');
  return digits ? `+${digits}` : '';
});

const canSend = computed(
  () => !!form.displayName.trim() && !!normalizedPhoneNumber.value
);

const submit = () => {
  if (!canSend.value) return;

  emit('send', {
    display_name: form.displayName.trim(),
    full_name: form.displayName.trim(),
    phone_number: normalizedPhoneNumber.value,
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
      <form
        class="w-full max-w-lg overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-xl"
        @submit.prevent="submit"
      >
        <header
          class="flex items-center justify-between gap-3 border-b border-n-weak p-4"
        >
          <div class="flex items-center gap-3">
            <div
              class="grid size-10 place-content-center rounded-lg bg-n-teal-9/15 text-n-teal-11"
            >
              <Icon icon="i-lucide-contact" class="size-5" />
            </div>
            <div>
              <h3 class="m-0 text-base font-semibold text-n-slate-12">
                {{ t('CONVERSATION.WHATSMEOW_CONTACT.SEND_CONTACT') }}
              </h3>
              <p class="m-0 text-sm text-n-slate-11">
                {{ t('CONVERSATION.WHATSMEOW_CONTACT.SEND_CONTACT_HINT') }}
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
            @click="$emit('close')"
          />
          <NextButton
            type="submit"
            icon="i-lucide-send"
            :label="t('CONVERSATION.WHATSMEOW_CONTACT.SEND_CONTACT')"
            :disabled="!canSend"
          />
        </footer>
      </form>
    </div>
  </div>
</template>
