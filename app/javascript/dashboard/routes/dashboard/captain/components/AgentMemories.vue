<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import ContactMemoryDialog from './ContactMemoryDialog.vue';

const props = defineProps({ agentId: { type: Number, required: true } });
const { t } = useI18n();
const search = ref('');
const page = ref(1);
const contacts = ref([]);
const total = ref(0);
const busy = ref(false);
const error = ref('');
const memoryDialog = ref(null);
let generation = 0;
const load = async () => {
  generation += 1;
  const currentGeneration = generation;
  busy.value = true;
  try {
    const { data } = await MarcosxAiAPI.getContactMemories({
      assistant_id: props.agentId,
      q: search.value,
      page: page.value,
    });
    if (currentGeneration !== generation) return;
    contacts.value = data.contacts;
    total.value = data.total;
    error.value = '';
  } catch (failure) {
    if (currentGeneration === generation)
      error.value =
        failure.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR');
  } finally {
    if (currentGeneration === generation) busy.value = false;
  }
};
watch(
  () => props.agentId,
  () => {
    if (page.value !== 1) page.value = 1;
    else load();
  },
  { immediate: true }
);
watch(page, load);
watch(
  search,
  useDebounceFn(() => {
    if (page.value === 1) load();
    else page.value = 1;
  }, 250)
);
</script>

<template>
  <section class="min-h-0 flex-1 space-y-5 overflow-y-auto p-6">
    <div class="flex flex-wrap items-center justify-between gap-4">
      <div>
        <h3 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ t('MARCOX_AI.WORKSPACE.MEMORIES') }}
        </h3>
        <p class="mb-0 mt-2 text-sm text-n-slate-11">
          {{ t('MARCOX_AI.WORKSPACE.MEMORY_HINT') }}
        </p>
      </div>
      <input
        v-model="search"
        class="reset-base h-10 w-full max-w-sm rounded-lg border border-n-weak bg-n-background px-3 text-sm"
        :placeholder="t('MARCOX_AI.WORKSPACE.SEARCH_CONTACT')"
        :aria-label="t('MARCOX_AI.WORKSPACE.SEARCH_CONTACT')"
      />
    </div>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
    <p v-if="!contacts.length && !busy" class="text-sm text-n-slate-11">
      {{ t('MARCOX_AI.WORKSPACE.NO_MEMORY') }}
    </p>
    <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
      <button
        v-for="contact in contacts"
        :key="contact.id"
        type="button"
        class="flex items-center gap-3 rounded-xl border border-n-weak p-4 text-start hover:bg-n-alpha-2"
        @click="memoryDialog.open(contact.id)"
      >
        <span
          class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-blue-3 text-n-blue-11"
          ><span class="i-lucide-brain size-5"
        /></span>
        <span
          class="min-w-0 flex-1 truncate text-sm font-medium text-n-slate-12"
          >{{ contact.name }}</span
        ><span class="i-lucide-chevron-right size-4 text-n-slate-10" />
      </button>
    </div>
    <div
      v-if="total > 25"
      class="flex items-center justify-end gap-3 text-sm text-n-slate-11"
    >
      <Button
        type="button"
        variant="ghost"
        icon="i-lucide-chevron-left"
        :disabled="busy || page === 1"
        :aria-label="t('MARCOX_AI.WORKSPACE.PREVIOUS')"
        @click="page -= 1"
      />
      <span>{{ page }} / {{ Math.ceil(total / 25) }}</span>
      <Button
        type="button"
        variant="ghost"
        icon="i-lucide-chevron-right"
        :disabled="busy || page * 25 >= total"
        :aria-label="t('MARCOX_AI.WORKSPACE.NEXT')"
        @click="page += 1"
      />
    </div>
    <ContactMemoryDialog ref="memoryDialog" />
  </section>
</template>
