<script setup>
import { computed, ref, watch } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import API from 'dashboard/api/marcosxAi';
import Button from 'dashboard/components-next/button/Button.vue';
import AiSelect from './AiSelect.vue';

const props = defineProps({
  modelValue: { type: Object, required: true },
  agentId: { type: Number, required: true },
  conversationId: { type: Number, default: null },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const search = ref('');
const contacts = ref([]);
const busy = ref(false);
const error = ref('');
const { run, abort } = useAbortableRequest();
const conversation = computed(
  () => props.conversationId || props.modelValue.conversation_id
);
const options = computed(() => [
  {
    value: 'global',
    label: t('MARCOX_AI.AUDIENCE.GLOBAL'),
    icon: 'i-lucide-globe',
  },
  ...(conversation.value
    ? [
        {
          value: 'conversation',
          label: t('MARCOX_AI.AUDIENCE.CONVERSATION', {
            id: conversation.value,
          }),
          icon: 'i-lucide-message-circle',
        },
      ]
    : []),
  {
    value: 'contacts',
    label: t('MARCOX_AI.AUDIENCE.CONTACTS'),
    icon: 'i-lucide-users',
  },
]);
const selected = computed(() => props.modelValue.audience_contacts || []);
const matches = computed(() =>
  contacts.value.filter(
    contact => !props.modelValue.contact_ids?.includes(contact.id)
  )
);
const change = value => {
  emit('update:modelValue', {
    ...props.modelValue,
    audience: value,
    conversation_id: value === 'conversation' ? conversation.value : null,
    contact_ids: value === 'contacts' ? props.modelValue.contact_ids || [] : [],
    audience_contacts: value === 'contacts' ? selected.value : [],
  });
};
const add = contact => {
  emit('update:modelValue', {
    ...props.modelValue,
    contact_ids: [...(props.modelValue.contact_ids || []), contact.id],
    audience_contacts: [...selected.value, contact],
  });
};
const remove = id => {
  emit('update:modelValue', {
    ...props.modelValue,
    contact_ids: props.modelValue.contact_ids.filter(value => value !== id),
    audience_contacts: selected.value.filter(contact => contact.id !== id),
  });
};
const load = async () => {
  if (props.modelValue.audience !== 'contacts') return;
  busy.value = true;
  error.value = '';
  try {
    const result = await run(signal =>
      API.getAudienceContacts(props.agentId, search.value, { signal })
    );
    if (result) contacts.value = result.data.contacts;
  } catch (failure) {
    error.value = t('MARCOX_AI.AUDIENCE.LOAD_ERROR');
  } finally {
    busy.value = false;
  }
};
watch(search, useDebounceFn(load, 250));
watch(
  () => [props.agentId, props.modelValue.audience],
  () => {
    abort();
    contacts.value = [];
    load();
  },
  { immediate: true }
);
</script>

<template>
  <div class="space-y-3 rounded-xl border border-n-weak bg-n-alpha-1 p-4">
    <label class="mb-0 block text-sm font-medium text-n-slate-12">
      {{ t('MARCOX_AI.AUDIENCE.TITLE') }}
    </label>
    <AiSelect
      :model-value="modelValue.audience || 'global'"
      :options="options"
      :label="t('MARCOX_AI.AUDIENCE.TITLE')"
      :teleport="false"
      in-flow
      @update:model-value="change"
    />
    <p class="m-0 text-xs leading-5 text-n-slate-11">
      {{
        t(
          `MARCOX_AI.AUDIENCE.HINT_${(modelValue.audience || 'global').toUpperCase()}`
        )
      }}
    </p>
    <template v-if="modelValue.audience === 'contacts'">
      <div v-if="selected.length" class="flex flex-wrap gap-2">
        <span
          v-for="contact in selected"
          :key="contact.id"
          class="inline-flex min-w-0 items-center gap-1 rounded-lg border border-n-weak bg-n-solid-2 ps-2 text-xs text-n-slate-12"
        >
          <span class="max-w-48 truncate">{{ contact.name }}</span>
          <Button
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :aria-label="t('MARCOX_AI.AUDIENCE.REMOVE', { name: contact.name })"
            @click="remove(contact.id)"
          />
        </span>
      </div>
      <input
        v-model="search"
        type="search"
        :aria-label="t('MARCOX_AI.AUDIENCE.SEARCH')"
        :placeholder="t('MARCOX_AI.AUDIENCE.SEARCH')"
        class="reset-base !mb-0 h-10 w-full rounded-lg border border-n-weak bg-n-solid-2 !px-3 text-sm text-n-slate-12"
      />
      <p v-if="error" class="m-0 text-xs text-n-ruby-11">{{ error }}</p>
      <div
        v-else
        class="max-h-36 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-2 p-1"
        :aria-busy="busy"
      >
        <button
          v-for="contact in matches"
          :key="contact.id"
          type="button"
          :disabled="selected.length >= 200"
          class="flex w-full items-center gap-2 rounded-md px-2.5 py-2 text-start text-sm text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 disabled:opacity-50"
          @click="add(contact)"
        >
          <span class="i-lucide-user-round size-4 shrink-0 text-n-slate-11" />
          <span class="min-w-0 flex-1 truncate">{{ contact.name }}</span>
          <span class="i-lucide-plus size-4 shrink-0 text-n-blue-11" />
        </button>
        <p
          v-if="!busy && !matches.length"
          class="m-0 px-2 py-3 text-xs text-n-slate-11"
        >
          {{ t('MARCOX_AI.AUDIENCE.NO_CONTACTS') }}
        </p>
      </div>
      <p v-if="!selected.length" class="m-0 text-xs text-n-amber-11">
        {{ t('MARCOX_AI.AUDIENCE.REQUIRED') }}
      </p>
    </template>
  </div>
</template>
