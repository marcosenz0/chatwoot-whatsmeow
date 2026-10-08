<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';

const props = defineProps({
  agent: { type: Object, required: true },
  inboxes: { type: Array, default: () => [] },
});
const { t } = useI18n();
const route = useRoute();
const coverage = ref(null);
const failed = ref(false);
const { run, isPending } = useAbortableRequest();
let request = 0;
const selectedInboxes = computed(() =>
  props.inboxes.filter(inbox => props.agent.inbox_ids.includes(inbox.id))
);
const allInboxes = computed(
  () =>
    props.inboxes.length > 0 &&
    selectedInboxes.value.length === props.inboxes.length
);
const pages = computed(() => Math.ceil((coverage.value?.total || 0) / 25));
const load = async (page = 1) => {
  request += 1;
  const current = request;
  const { id } = props.agent;
  failed.value = false;
  try {
    const result = await run(signal =>
      MarcosxAiAPI.getAssistantCoverage(id, page, { signal })
    );
    if (result && current === request) coverage.value = result.data;
  } catch (error) {
    if (current !== request) return;
    failed.value = true;
    useAlert(error.response?.data?.error || t('MARCOX_AI.ERROR'));
  }
};
watch(
  () => [
    props.agent.id,
    props.agent.config.auto_response_enabled,
    props.agent.config.auto_start,
    props.agent.updated_at,
  ],
  () => {
    coverage.value = null;
    load();
  },
  { immediate: true }
);
</script>

<template>
  <section class="min-h-0 min-w-0 flex-1 overflow-y-auto px-6 py-6 xl:px-10">
    <div class="mb-6 flex flex-wrap items-start justify-between gap-4">
      <div>
        <h3 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ t('MARCOX_AI.COVERAGE.TITLE') }}
        </h3>
        <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
          {{ t('MARCOX_AI.COVERAGE.BODY') }}
        </p>
      </div>
      <Button
        icon="i-lucide-refresh-cw"
        variant="outline"
        color="slate"
        :label="t('MARCOX_AI.REFRESH')"
        :is-loading="isPending"
        @click="load(coverage?.page || 1)"
      />
    </div>
    <p v-if="failed" class="text-sm text-n-ruby-11">
      {{ t('MARCOX_AI.ERROR') }}
    </p>
    <div v-else-if="!coverage" class="flex justify-center py-12">
      <Spinner />
    </div>
    <template v-else>
      <div class="flex items-start gap-4 rounded-xl border border-n-weak p-5">
        <span
          class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
        >
          <span
            class="size-5"
            :class="
              coverage.mode === 'automatic'
                ? 'i-lucide-inbox'
                : 'i-lucide-messages-square'
            "
          />
        </span>
        <div>
          <h4 class="m-0 text-sm font-semibold text-n-slate-12">
            {{
              t(
                coverage.mode === 'automatic'
                  ? 'MARCOX_AI.COVERAGE.AUTOMATIC'
                  : 'MARCOX_AI.COVERAGE.INDIVIDUAL'
              )
            }}
          </h4>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{
              t(
                coverage.mode === 'automatic'
                  ? 'MARCOX_AI.COVERAGE.AUTOMATIC_HINT'
                  : 'MARCOX_AI.COVERAGE.INDIVIDUAL_HINT'
              )
            }}
          </p>
          <p
            v-if="
              coverage.mode === 'individual' &&
              agent.config.auto_response_enabled &&
              !agent.config.auto_start
            "
            class="mb-0 mt-2 text-xs leading-5 text-n-slate-11"
          >
            {{ t('MARCOX_AI.COVERAGE.MANUAL_START') }}
          </p>
        </div>
      </div>
      <div v-if="coverage.mode === 'automatic'" class="mt-6">
        <p class="text-sm font-medium text-n-slate-12">
          {{
            t(
              allInboxes
                ? 'MARCOX_AI.COVERAGE.ALL_INBOXES'
                : 'MARCOX_AI.COVERAGE.SELECTED_INBOXES',
              { count: selectedInboxes.length }
            )
          }}
        </p>
        <div class="flex flex-wrap gap-2">
          <span
            v-for="inbox in selectedInboxes"
            :key="inbox.id"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-11"
          >
            {{ inbox.name }}
          </span>
        </div>
      </div>
      <template v-else>
        <p class="mb-3 mt-6 text-sm font-medium text-n-slate-12">
          {{ t('MARCOX_AI.COVERAGE.COUNT', { count: coverage.total }) }}
        </p>
        <p
          v-if="!coverage.total"
          class="rounded-xl border border-n-weak p-6 text-sm leading-6 text-n-slate-11"
        >
          {{ t('MARCOX_AI.COVERAGE.EMPTY') }}
        </p>
        <div
          v-else
          class="divide-y divide-n-weak rounded-xl border border-n-weak"
        >
          <RouterLink
            v-for="conversation in coverage.conversations"
            :key="conversation.id"
            :to="{
              name: 'inbox_conversation',
              params: {
                accountId: route.params.accountId,
                conversationId: conversation.id,
              },
            }"
            class="flex items-center gap-3 p-4 hover:bg-n-alpha-1"
          >
            <Avatar
              :src="conversation.avatar_url || ''"
              :name="conversation.contact_name"
              :size="36"
            />
            <div class="min-w-0 flex-1">
              <p class="m-0 truncate text-sm font-semibold text-n-slate-12">
                {{ conversation.contact_name }}
              </p>
              <p class="mb-0 mt-1 truncate text-xs text-n-slate-11">
                {{ `${conversation.inbox_name} · #${conversation.id}` }}
              </p>
            </div>
            <span
              class="hidden items-center gap-2 text-xs text-n-teal-11 sm:flex"
            >
              <span class="i-lucide-bot size-4 shrink-0" />
              {{
                t(
                  conversation.processing
                    ? 'MARCOX_AI.CONVERSATION.WORKING'
                    : 'MARCOX_AI.CONVERSATION.ON'
                )
              }}
            </span>
            <span
              class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-11"
            />
          </RouterLink>
        </div>
        <div v-if="pages > 1" class="mt-4 flex items-center justify-end gap-3">
          <Button
            variant="outline"
            color="slate"
            icon="i-lucide-chevron-left"
            :label="t('MARCOX_AI.COVERAGE.PREVIOUS')"
            :disabled="coverage.page <= 1 || isPending"
            @click="load(coverage.page - 1)"
          />
          <span class="text-xs text-n-slate-11">{{
            t('MARCOX_AI.COVERAGE.PAGE', { page: coverage.page, pages })
          }}</span>
          <Button
            variant="outline"
            color="slate"
            icon="i-lucide-chevron-right"
            :label="t('MARCOX_AI.COVERAGE.NEXT')"
            :disabled="coverage.page >= pages || isPending"
            @click="load(coverage.page + 1)"
          />
        </div>
      </template>
    </template>
  </section>
</template>
