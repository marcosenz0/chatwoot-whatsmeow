<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import ContactMemoryDialog from './ContactMemoryDialog.vue';

const props = defineProps({ agentId: { type: Number, required: true } });
const { t } = useI18n();
const search = ref('');
const page = ref(1);
const pageSize = ref(50);
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
    pageSize.value = data.per_page || 25;
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
  <section class="min-h-0 min-w-0 flex-1 overflow-y-auto p-4 sm:p-6">
    <div class="mx-auto w-full max-w-6xl space-y-5">
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
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <p v-if="!contacts.length && !busy" class="text-sm text-n-slate-11">
        {{ t('MARCOX_AI.WORKSPACE.NO_MEMORY') }}
      </p>
      <div class="grid gap-2 md:grid-cols-2 xl:grid-cols-3">
        <button
          v-for="contact in contacts"
          :key="contact.id"
          type="button"
          class="flex min-w-0 items-center gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-3 text-start transition-colors hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
          @click="memoryDialog.open(contact.id)"
        >
          <Avatar
            :src="contact.avatar_url || ''"
            :name="contact.name || ''"
            :size="36"
            loading="lazy"
          />
          <span
            class="min-w-0 flex-1 truncate text-sm font-medium text-n-slate-12"
            >{{ contact.name }}</span
          ><span class="i-lucide-chevron-right size-4 text-n-slate-10" />
        </button>
      </div>
      <div
        v-if="total > pageSize"
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
        <span>{{ page }} / {{ Math.ceil(total / pageSize) }}</span>
        <Button
          type="button"
          variant="ghost"
          icon="i-lucide-chevron-right"
          :disabled="busy || page * pageSize >= total"
          :aria-label="t('MARCOX_AI.WORKSPACE.NEXT')"
          @click="page += 1"
        />
      </div>
    </div>
    <ContactMemoryDialog ref="memoryDialog" />
  </section>
</template>
