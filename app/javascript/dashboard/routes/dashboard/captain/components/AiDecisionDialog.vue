<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';

const props = defineProps({
  conversationId: { type: Number, required: true },
  messageId: { type: Number, required: true },
});
const emit = defineEmits(['close']);
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const dialog = ref(null);
const report = ref(null);
const error = ref('');
const search = ref('');
const normalize = text =>
  text
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase();
const sources = computed(() =>
  (report.value?.sources || []).map(source => {
    const needle = normalize(search.value.trim());
    const matches = source.text
      .split('\n')
      .flatMap(line => {
        const normalized = normalize(line);
        const index = needle
          ? normalized.indexOf(needle)
          : normalized.search(
              /human|pessoa|equipe|confirm|verific|handoff|agenda|presencial|acao externa/
            );
        if (index < 0) return [];
        return [line.slice(Math.max(0, index - 80), index + 180).trim()];
      })
      .slice(0, 4);
    return { ...source, matches };
  })
);
const { run, abort, isPending } = useAbortableRequest();
const close = () => {
  abort();
  emit('close');
};
const edit = (section, field, excerpt = '') => {
  dialog.value.close();
  router.push({
    path: `/app/accounts/${route.params.accountId}/captain/overview`,
    query: {
      agent: report.value.assistant.id,
      section,
      ...(field ? { focus: field } : {}),
    },
    state: { marcosxAiExcerpt: excerpt },
  });
};
onMounted(async () => {
  dialog.value.open();
  try {
    const response = await run(signal =>
      MarcosxAiAPI.getConversationDecision(
        props.conversationId,
        props.messageId,
        { signal }
      )
    );
    if (response) report.value = response.data;
  } catch (exception) {
    error.value =
      exception.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR');
  }
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="3xl"
    :title="t('MARCOX_AI.DECISION.REVIEW')"
    :description="t('MARCOX_AI.DECISION.HINT')"
    :show-confirm-button="false"
    :cancel-button-label="t('MARCOX_AI.WORKSPACE.CLOSE')"
    @close="close"
  >
    <div
      class="max-h-[calc(100dvh-16rem)] space-y-4 overflow-y-auto pe-2 text-n-slate-12"
    >
      <p v-if="isPending" class="text-sm text-n-slate-11">
        {{ t('MARCOX_AI.DECISION.LOADING') }}
      </p>
      <p v-if="error" class="text-sm text-n-ruby-11">{{ error }}</p>
      <template v-if="report">
        <div class="rounded-lg border border-n-weak bg-n-solid-2 p-4">
          <p class="m-0 font-semibold text-n-slate-12">
            {{ report.assistant.name }}
          </p>
          <p class="mb-0 mt-2 whitespace-pre-wrap text-sm text-n-slate-11">
            {{ report.note }}
          </p>
        </div>
        <p
          class="rounded-lg bg-n-amber-2 p-3 text-xs leading-5 text-n-amber-11"
        >
          {{
            t(
              report.snapshot
                ? 'MARCOX_AI.DECISION.RECORDED'
                : 'MARCOX_AI.DECISION.LEGACY'
            )
          }}
          <span v-if="report.configuration_changed">{{
            t('MARCOX_AI.DECISION.CHANGED')
          }}</span>
        </p>
        <div
          v-if="report.snapshot"
          class="space-y-2 rounded-lg border border-n-weak p-4 text-sm"
        >
          <p class="m-0">
            {{ t('MARCOX_AI.DECISION.REASON') }}:
            {{ report.snapshot.reason || report.note }}
          </p>
          <p class="m-0">
            {{ t('MARCOX_AI.DECISION.PAUSE_RECORDED') }}:
            {{
              t(
                `MARCOX_AI.DECISION.${report.snapshot.automatic_handoff_enabled ? 'ON' : 'OFF'}`
              )
            }}
          </p>
          <div
            v-for="rule in report.snapshot.rules"
            :key="rule.id"
            class="rounded-lg bg-n-alpha-1 p-3"
          >
            <p class="m-0 font-medium">
              {{ rule.name }} ·
              {{
                t(
                  rule.action === 'pause'
                    ? 'MARCOX_AI.AUTOMATION.ACTION_PAUSE'
                    : 'MARCOX_AI.AUTOMATION.ACTION_NOTIFY'
                )
              }}
            </p>
            <p class="mb-0 mt-1 text-xs text-n-slate-11">
              {{ rule.description }}
            </p>
          </div>
        </div>
        <div
          class="flex flex-col items-start justify-between gap-3 rounded-lg border border-n-weak p-4 sm:flex-row sm:items-center"
        >
          <div class="space-y-1 text-sm">
            <p class="m-0">{{ t('MARCOX_AI.DECISION.NOTIFICATIONS') }}</p>
            <p class="m-0 text-xs text-n-slate-11">
              {{ t('MARCOX_AI.AUTOMATION.PAUSE_HANDOFF') }}:
              {{
                t(
                  `MARCOX_AI.DECISION.${report.pause_on_handoff ? 'ON' : 'OFF'}`
                )
              }}
            </p>
            <p class="m-0 text-xs text-n-slate-11">
              {{ t('MARCOX_AI.CONVERSATION.AUTO_PAUSE') }}:
              {{
                t(
                  `MARCOX_AI.DECISION.${report.automatic_handoff_enabled === false ? 'OFF' : 'ON'}`
                )
              }}
            </p>
          </div>
          <Button
            icon="i-lucide-arrow-up-right"
            class="shrink-0"
            variant="faded"
            color="blue"
            :label="t('MARCOX_AI.DECISION.OPEN')"
            @click="edit('notifications')"
          />
        </div>
        <p class="text-xs leading-5 text-n-slate-11">
          {{ t('MARCOX_AI.DECISION.SOURCES_HINT') }}
        </p>
        <input
          v-model="search"
          :placeholder="t('MARCOX_AI.DECISION.SEARCH')"
          :aria-label="t('MARCOX_AI.DECISION.SEARCH')"
          class="reset-base h-10 w-full rounded-lg border border-n-weak bg-n-background px-3 text-sm"
        />
        <details
          v-for="source in sources"
          :key="source.field"
          :open="source.matches.length > 0"
          class="rounded-lg border border-n-weak p-4"
        >
          <summary class="cursor-pointer text-sm font-semibold">
            {{ t(`MARCOX_AI.DECISION.SOURCES.${source.field.toUpperCase()}`) }}
          </summary>
          <div v-if="source.matches.length" class="mt-3 space-y-2">
            <p class="m-0 text-xs text-n-slate-11">
              {{ t('MARCOX_AI.DECISION.EXCERPTS') }}
            </p>
            <div
              v-for="excerpt in source.matches"
              :key="excerpt"
              class="space-y-2 rounded-lg bg-n-alpha-1 p-3"
            >
              <p
                class="m-0 whitespace-pre-wrap break-words text-xs leading-5 text-n-slate-12"
              >
                {{ excerpt }}
              </p>
              <Button
                v-if="source.editable"
                size="sm"
                icon="i-lucide-search"
                variant="link"
                color="blue"
                :label="t('MARCOX_AI.DECISION.GO_EXCERPT')"
                @click="edit(source.section, source.field, excerpt)"
              />
            </div>
          </div>
          <details class="mt-3">
            <summary class="cursor-pointer text-xs text-n-slate-11">
              {{ t('MARCOX_AI.DECISION.FULL_SOURCE') }}
            </summary>
            <pre
              class="mt-2 max-h-56 overflow-y-auto whitespace-pre-wrap break-words text-xs leading-5 text-n-slate-11"
              >{{ source.text }}</pre
            >
          </details>
          <Button
            v-if="source.editable"
            icon="i-lucide-notebook-pen"
            variant="faded"
            color="blue"
            :label="t('MARCOX_AI.DECISION.EDIT_SOURCE')"
            @click="edit(source.section, source.field)"
          />
          <p v-else class="mb-0 text-xs text-n-slate-11">
            {{ t('MARCOX_AI.DECISION.PLATFORM_HINT') }}
          </p>
        </details>
      </template>
    </div>
  </Dialog>
</template>
