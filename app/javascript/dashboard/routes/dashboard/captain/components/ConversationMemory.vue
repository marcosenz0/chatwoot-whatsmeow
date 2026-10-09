<script setup>
import { ref, watch } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import AiSelect from './AiSelect.vue';

const props = defineProps({ conversationId: { type: Number, required: true } });
const emit = defineEmits(['updated']);
const { t } = useI18n();
const memory = ref(null);
const mode = ref('summary_recent');
const recentLimit = ref(20);
const sourceId = ref(null);
const busy = ref(false);
let generation = 0;
const load = async () => {
  const version = generation;
  try {
    const { data } = await MarcosxAiAPI.getMemory(props.conversationId);
    if (version !== generation) return;
    memory.value = data.memory;
    mode.value =
      data.memory.mode === 'legacy' ? 'summary_recent' : data.memory.mode;
    recentLimit.value = data.memory.recent_limit;
  } catch (error) {
    if (version === generation)
      useAlert(
        error.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR')
      );
  }
};
watch(
  () => props.conversationId,
  () => {
    generation += 1;
    load();
  },
  { immediate: true }
);
useIntervalFn(() => {
  if (memory.value?.rebuild?.status === 'processing') load();
}, 2500);
const perform = async action => {
  busy.value = true;
  try {
    if (action === 'save') {
      await MarcosxAiAPI.updateMemory(props.conversationId, {
        mode: mode.value,
        recent_limit: recentLimit.value,
      });
      emit('updated');
    } else if (action === 'rebuild')
      await MarcosxAiAPI.rebuildMemory(props.conversationId);
    else if (action === 'link')
      await MarcosxAiAPI.linkMemory(props.conversationId, sourceId.value);
    else await MarcosxAiAPI.unlinkMemory(props.conversationId);
    await load();
  } catch (error) {
    useAlert(error.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR'));
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <details v-if="memory" class="space-y-3 rounded-lg border border-n-weak p-3">
    <summary class="cursor-pointer text-sm font-semibold">
      {{ t('MARCOX_AI.AUTOMATION.MEMORY_TITLE') }}
    </summary>
    <AiSelect
      v-model="mode"
      class="mt-3"
      :options="
        ['summary_recent', 'selected_only'].map(value => ({
          value,
          label: t(`MARCOX_AI.AUTOMATION.MEMORY_${value.toUpperCase()}`),
        }))
      "
      :label="t('MARCOX_AI.AUTOMATION.MEMORY_MODE')"
    />
    <label class="block text-xs text-n-slate-11">
      {{ t('MARCOX_AI.AUTOMATION.RECENT_LIMIT') }}
      <input
        v-model.number="recentLimit"
        type="number"
        min="1"
        max="300"
        class="reset-base mt-2 h-10 w-full rounded-lg border border-n-weak bg-n-background px-3"
      />
    </label>
    <Button
      size="sm"
      variant="outline"
      :disabled="busy"
      :label="t('MARCOX_AI.AUTOMATION.SAVE_MEMORY')"
      @click="perform('save')"
    />
    <p class="text-xs text-n-slate-11">
      {{
        t('MARCOX_AI.AUTOMATION.SUMMARY_INFO', {
          count: memory.summarized_count,
          recent: memory.recent_limit,
          date: memory.updated_at || '—',
        })
      }}
    </p>
    <p v-if="memory.stale" class="text-xs text-n-amber-11">
      {{ t('MARCOX_AI.AUTOMATION.SUMMARY_STALE') }}
    </p>
    <p
      class="max-h-48 overflow-y-auto whitespace-pre-wrap text-sm text-n-slate-11"
    >
      {{ memory.summary || t('MARCOX_AI.AUTOMATION.EMPTY_SUMMARY') }}
    </p>
    <p v-if="memory.rebuild" class="text-xs text-n-slate-11">
      {{
        t(`MARCOX_AI.AUTOMATION.REBUILD_${memory.rebuild.status.toUpperCase()}`)
      }}
    </p>
    <Button
      size="sm"
      variant="outline"
      :disabled="
        busy ||
        memory.rebuild?.status === 'processing' ||
        mode !== 'summary_recent'
      "
      :label="t('MARCOX_AI.AUTOMATION.REBUILD')"
      @click="perform('rebuild')"
    />
    <div class="space-y-3 border-t border-n-weak pt-3">
      <p class="text-xs text-n-slate-11">
        {{ t('MARCOX_AI.AUTOMATION.LINK_HINT') }}
      </p>
      <p
        v-for="link in memory.links"
        :key="link.id"
        class="text-xs text-n-slate-11"
      >
        #{{ link.id }} · {{ link.inbox }}
      </p>
      <input
        v-model.number="sourceId"
        type="number"
        min="1"
        class="reset-base h-10 w-full rounded-lg border border-n-weak bg-n-background px-3"
        :placeholder="t('MARCOX_AI.AUTOMATION.SOURCE_CONVERSATION')"
      />
      <Button
        size="sm"
        variant="outline"
        :disabled="busy || !sourceId"
        :label="t('MARCOX_AI.AUTOMATION.APPROVE_LINK')"
        @click="perform('link')"
      />
      <Button
        v-if="memory.links.length"
        size="sm"
        variant="link"
        :disabled="busy"
        :label="t('MARCOX_AI.AUTOMATION.REMOVE_LINKS')"
        @click="perform('unlink')"
      />
    </div>
  </details>
</template>
