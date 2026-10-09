<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AiSelect from './AiSelect.vue';

const props = defineProps({
  users: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
});
const settings = defineModel({ type: Object, required: true });
const { t } = useI18n();
const numbers = computed({
  get: () => settings.value.whatsapp_numbers.join('\n'),
  set: value => {
    settings.value.whatsapp_numbers = [
      ...new Set(value.split(/[\s,;]+/).filter(Boolean)),
    ];
  },
});
const options = computed(() => [
  { value: null, label: t('MARCOX_AI.AUTOMATION.SELECT_INBOX') },
  ...props.inboxes.map(inbox => ({ value: inbox.id, label: inbox.name })),
]);
const toggleUser = id => {
  const ids = settings.value.user_ids;
  settings.value.user_ids = ids.includes(id)
    ? ids.filter(value => value !== id)
    : [...ids, id];
};
</script>

<template>
  <div class="space-y-3">
    <p class="m-0 text-sm font-medium">
      {{ t('MARCOX_AI.AUTOMATION.PANEL_USERS') }}
    </p>
    <label
      v-for="user in users"
      :key="user.id"
      class="flex items-center gap-2 text-sm"
    >
      <input
        type="checkbox"
        class="reset-base"
        :checked="settings.user_ids.includes(user.id)"
        @change="toggleUser(user.id)"
      />
      {{ user.name }}
    </label>
    <label class="block text-sm">
      {{ t('MARCOX_AI.AUTOMATION.WHATSAPP_NUMBERS') }}
      <textarea
        v-model="numbers"
        rows="3"
        class="reset-base mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3"
        :placeholder="t('MARCOX_AI.AUTOMATION.NUMBERS_HINT')"
      />
    </label>
    <AiSelect
      v-model="settings.inbox_id"
      :options="options"
      :label="t('MARCOX_AI.AUTOMATION.SENDER_INBOX')"
    />
  </div>
</template>
