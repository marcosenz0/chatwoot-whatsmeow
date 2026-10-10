<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import AiSelect from './AiSelect.vue';

const props = defineProps({
  users: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
});
const settings = defineModel({ type: Object, required: true });
const { t } = useI18n();
const number = ref('');
const error = ref('');
const addNumber = () => {
  const normalized = number.value.replace(/[\s().-]/g, '');
  if (!/^\+[1-9]\d{7,14}$/.test(normalized)) {
    error.value = t('MARCOX_AI.WORKSPACE.INVALID_NUMBER');
    return;
  }
  if (!settings.value.whatsapp_numbers.includes(normalized))
    settings.value.whatsapp_numbers.push(normalized);
  number.value = '';
  error.value = '';
};
const removeNumber = value => {
  settings.value.whatsapp_numbers = settings.value.whatsapp_numbers.filter(
    item => item !== value
  );
};
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
  <div class="grid gap-5 lg:grid-cols-2">
    <div class="space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4">
      <p class="m-0 text-sm font-medium">
        {{ t('MARCOX_AI.AUTOMATION.PANEL_USERS') }}
      </p>
      <label
        v-for="user in users"
        :key="user.id"
        class="flex items-center gap-3 rounded-lg border border-n-weak p-3 text-sm"
      >
        <input
          type="checkbox"
          class="reset-base"
          :checked="settings.user_ids.includes(user.id)"
          @change="toggleUser(user.id)"
        />
        {{ user.name }}
      </label>
    </div>
    <div class="space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4">
      <p class="m-0 text-sm font-medium">
        {{ t('MARCOX_AI.AUTOMATION.WHATSAPP_NUMBERS') }}
      </p>
      <div
        v-for="value in settings.whatsapp_numbers"
        :key="value"
        class="flex items-center justify-between gap-3 rounded-lg border border-n-weak p-3"
      >
        <span class="text-sm text-n-slate-12">{{ value }}</span>
        <Button
          type="button"
          size="sm"
          variant="ghost"
          color="ruby"
          icon="i-lucide-trash-2"
          :aria-label="
            t('MARCOX_AI.WORKSPACE.REMOVE_NUMBER', { number: value })
          "
          @click="removeNumber(value)"
        />
      </div>
      <div class="flex gap-2">
        <input
          v-model="number"
          type="tel"
          autocomplete="tel"
          class="reset-base h-10 min-w-0 flex-1 rounded-lg border border-n-weak bg-n-background px-3 text-sm"
          :placeholder="t('MARCOX_AI.WORKSPACE.NUMBER_PLACEHOLDER')"
          :aria-label="t('MARCOX_AI.AUTOMATION.WHATSAPP_NUMBERS')"
          @keydown.enter.prevent="addNumber"
        />
        <Button
          type="button"
          variant="outline"
          icon="i-lucide-plus"
          :label="t('MARCOX_AI.WORKSPACE.ADD_NUMBER')"
          :disabled="!number.trim() || settings.whatsapp_numbers.length >= 20"
          @click="addNumber"
        />
      </div>
      <p v-if="error" role="alert" class="text-xs text-n-ruby-11">
        {{ error }}
      </p>
      <p class="text-xs text-n-slate-11">
        {{ t('MARCOX_AI.WORKSPACE.NUMBER_HINT') }}
      </p>
      <label class="block text-sm"
        >{{ t('MARCOX_AI.AUTOMATION.SENDER_INBOX') }}
        <AiSelect
          v-model="settings.inbox_id"
          :options="options"
          :label="t('MARCOX_AI.AUTOMATION.SENDER_INBOX')"
        />
      </label>
    </div>
  </div>
</template>
