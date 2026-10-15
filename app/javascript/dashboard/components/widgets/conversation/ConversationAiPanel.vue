<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AiSelect from 'dashboard/routes/dashboard/captain/components/AiSelect.vue';
import AiToggleRow from 'dashboard/routes/dashboard/captain/components/AiToggleRow.vue';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import ConversationMemory from 'dashboard/routes/dashboard/captain/components/ConversationMemory.vue';
import AgentAlertList from 'dashboard/routes/dashboard/captain/components/AgentAlertList.vue';
import AiPanelSection from 'dashboard/routes/dashboard/captain/components/AiPanelSection.vue';
import AgentResources from 'dashboard/routes/dashboard/captain/components/AgentResources.vue';
import AgentPixKeys from 'dashboard/routes/dashboard/captain/components/AgentPixKeys.vue';
import AgentNotificationTargets from 'dashboard/routes/dashboard/captain/components/AgentNotificationTargets.vue';
import PixIcon from 'next/icon/PixIcon.vue';
import ConversationVoiceDraft from './ConversationVoiceDraft.vue';

const props = defineProps({
  chat: { type: Object, required: true },
  state: { type: Object, default: null },
  assistants: { type: Array, default: () => [] },
});
const emit = defineEmits(['updated']);
const { t } = useI18n();
const { isAdmin } = useAdmin();
const dialog = ref(null);
const replyReview = ref(null);
const visible = ref(false);
const working = ref(false);
const assistantId = ref(null);
const globalScope = ref(false);
const quickEditor = ref(null);
const quickFiles = ref(null);
const quickPix = ref(null);
const quickNotices = ref(null);
const shortcutCounts = ref({ resources: null, pix: null, notices: null });
const shortcutError = ref(false);
const pendingCount = ref(0);
let shortcutGeneration = 0;
const loadShortcuts = async () => {
  const id = assistantId.value;
  if (!visible.value || !isAdmin.value || !id) return;
  shortcutGeneration += 1;
  const version = shortcutGeneration;
  try {
    const [resources, pix, notices] = await Promise.all([
      MarcosxAiAPI.getResources(id),
      MarcosxAiAPI.getPixKeys(id),
      MarcosxAiAPI.getNotificationTargets(id),
    ]);
    if (version !== shortcutGeneration || !visible.value) return;
    shortcutCounts.value = {
      resources: resources.data.total,
      pix: pix.data.pix_keys.filter(item => item.enabled).length,
      notices: notices.data.notification_targets.filter(item => item.enabled)
        .length,
    };
    shortcutError.value = false;
  } catch (error) {
    if (version === shortcutGeneration) shortcutError.value = true;
  }
};
const openQuick = async kind => {
  quickEditor.value = kind;
  await nextTick();
  ({ resources: quickFiles, pix: quickPix, notices: quickNotices })[
    kind
  ].value.openCreate();
};
watch(assistantId, () => {
  quickEditor.value = null;
  shortcutCounts.value = { resources: null, pix: null, notices: null };
  loadShortcuts();
});
const analysis = ref({ status: 'idle' });
const parts = ref([]);
const totalMessages = ref(0);
const messagesLimit = ref(null);
const contextChanged = computed(
  () => (analysis.value.messages_limit ?? null) !== messagesLimit.value
);
const selectedMessages = computed(() =>
  Math.min(messagesLimit.value || totalMessages.value, totalMessages.value)
);
const { run, abort } = useAbortableRequest();
const selected = computed(() =>
  props.assistants.find(item => item.id === assistantId.value)
);
const options = computed(() =>
  props.assistants.map(item => ({
    value: item.id,
    label: item.name,
    description: item.model,
    icon: 'i-lucide-bot',
  }))
);
const active = computed(
  () =>
    props.state?.status === 'active' &&
    props.state.enabled &&
    props.state.available
);
const available = computed(
  () =>
    selected.value?.available &&
    !['resolved', 'snoozed'].includes(props.chat.status)
);
const processing = computed(() => analysis.value.status === 'processing');
const hasResponse = computed(
  () =>
    parts.value.some(part => part.trim()) ||
    analysis.value.plan?.reaction ||
    analysis.value.plan?.handoff
);
const notifyError = error =>
  useAlert(error.response?.data?.error || t('MARCOX_AI.CONVERSATION.ERROR'));
const setReport = report => {
  analysis.value = report;
  parts.value = [...(report.plan?.messages || [])];
  if (report.status === 'ready' && !parts.value.length) parts.value = [''];
};
const fetchReport = async () => {
  const { id } = props.chat;
  try {
    const result = await run(signal =>
      MarcosxAiAPI.getConversationAnalysis(id, { signal })
    );
    if (result && visible.value && id === props.chat.id) {
      totalMessages.value =
        result.data.context?.total_messages_count ||
        result.data.analysis.messages_count ||
        0;
      messagesLimit.value = result.data.context?.messages_limit ?? null;
      setReport(result.data.analysis);
    }
  } catch (error) {
    notifyError(error);
  }
};
useIntervalFn(() => {
  if (visible.value && processing.value) fetchReport();
}, 2500);
const close = () => {
  visible.value = false;
  shortcutGeneration += 1;
  quickEditor.value = null;
  abort();
};
const open = () => {
  assistantId.value =
    props.state?.assistant_id ||
    props.assistants.find(item => item.available)?.id ||
    null;
  setReport({ status: 'idle' });
  totalMessages.value = 0;
  messagesLimit.value = null;
  globalScope.value = false;
  pendingCount.value = 0;
  visible.value = true;
  dialog.value.open();
  loadShortcuts();
  fetchReport();
};
watch(
  () => props.chat.id,
  () => {
    dialog.value?.close();
    close();
    working.value = false;
  }
);
watch(
  () => props.state?.assistant_id,
  id => {
    if (visible.value && id) assistantId.value = id;
  }
);
const act = async action => {
  const { id } = props.chat;
  working.value = true;
  try {
    const { data } = await MarcosxAiAPI.updateConversationState(id, {
      action,
      reason: 'agent_action',
      ...(assistantId.value !== props.state?.assistant_id
        ? { assistant_id: assistantId.value }
        : {}),
    });
    if (id !== props.chat.id) return;
    emit('updated', data.state);
    if (action === 'select') setReport({ status: 'idle' });
    const label =
      {
        reply_now: 'MARCOX_AI.CONVERSATION.REPLY_NOW_OK',
        resume: 'MARCOX_AI.CONVERSATION.RESUMED_OK',
      }[action] || 'MARCOX_AI.CONVERSATION.PAUSED_OK';
    useAlert(t(label));
  } catch (error) {
    if (id === props.chat.id) notifyError(error);
  } finally {
    if (id === props.chat.id) working.value = false;
  }
};
const selectAssistant = id => {
  assistantId.value = id;
  act('select');
};
const setAutoPause = async enabled => {
  const { id } = props.chat;
  working.value = true;
  try {
    const { data } = await MarcosxAiAPI.updateConversationState(id, {
      action: 'set_auto_pause',
      automatic_handoff_enabled: enabled,
    });
    if (id === props.chat.id) {
      emit('updated', data.state);
      useAlert(t('MARCOX_AI.CONVERSATION.AUTO_PAUSE_SAVED'));
    }
  } catch (error) {
    if (id === props.chat.id) notifyError(error);
  } finally {
    if (id === props.chat.id) working.value = false;
  }
};
const analyze = async () => {
  const { id } = props.chat;
  working.value = true;
  abort();
  try {
    const { data } = await MarcosxAiAPI.analyzeConversation(
      id,
      assistantId.value,
      messagesLimit.value
    );
    if (id !== props.chat.id) return;
    setReport(data.analysis);
    const result = await MarcosxAiAPI.getConversationState(id);
    if (id === props.chat.id) emit('updated', result.data.state);
  } catch (error) {
    if (id === props.chat.id) notifyError(error);
  } finally {
    if (id === props.chat.id) working.value = false;
  }
};
const send = async () => {
  const { id } = props.chat;
  working.value = true;
  try {
    const { data } = await MarcosxAiAPI.sendConversationAnalysis(
      id,
      analysis.value.id,
      parts.value.filter(part => part.trim())
    );
    if (id !== props.chat.id) return;
    analysis.value = { ...analysis.value, status: 'sent' };
    emit('updated', data.state);
    useAlert(t('MARCOX_AI.ANALYSIS.SENT'));
  } catch (error) {
    if (id === props.chat.id) {
      notifyError(error);
      fetchReport();
    }
  } finally {
    if (id === props.chat.id) working.value = false;
  }
};
defineExpose({ open });
const selectContext = event => {
  const value = Number(event.target.value);
  messagesLimit.value = value === totalMessages.value ? null : value;
};
</script>

<template>
  <ConversationVoiceDraft
    ref="replyReview"
    :conversation-id="chat.id"
    :assistant-id="assistantId"
  />
  <template v-if="visible && isAdmin && assistantId">
    <AgentResources
      v-if="quickEditor === 'resources'"
      :key="assistantId"
      ref="quickFiles"
      :agent-id="assistantId"
      :conversation-id="chat.id"
      :global-scope="globalScope"
      compact
      @saved="loadShortcuts"
    />
    <AgentPixKeys
      v-if="quickEditor === 'pix'"
      :key="assistantId"
      ref="quickPix"
      :agent-id="assistantId"
      :conversation-id="chat.id"
      :global-scope="globalScope"
      compact
      @saved="loadShortcuts"
    />
    <AgentNotificationTargets
      v-if="quickEditor === 'notices'"
      :key="assistantId"
      ref="quickNotices"
      :agent-id="assistantId"
      :conversation-id="chat.id"
      :global-scope="globalScope"
      compact
      @saved="loadShortcuts"
    />
  </template>
  <Dialog
    ref="dialog"
    width="3xl"
    overflow-y-auto
    :aria-label="t('MARCOX_AI.PANEL.TITLE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="close"
  >
    <div class="space-y-3">
      <header class="mb-5 flex flex-wrap items-start justify-between gap-3">
        <div class="flex min-w-0 items-start gap-3">
          <span
            class="i-lucide-sparkles mt-0.5 size-7 shrink-0 text-n-blue-11"
          />
          <div class="min-w-0">
            <h3 class="m-0 text-lg font-semibold text-n-slate-12">
              {{ t('MARCOX_AI.PANEL.TITLE') }}
            </h3>
            <p class="mb-0 mt-1 truncate text-sm text-n-slate-11">
              {{
                t('MARCOX_AI.PANEL.CONTACT', {
                  name: chat.meta?.sender?.name || '',
                  id: chat.id,
                })
              }}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-3">
          <AiToggleRow
            v-if="isAdmin"
            v-model="globalScope"
            class="!py-0"
            :label="t('MARCOX_AI.PANEL.GLOBAL')"
          />
          <Button
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :aria-label="t('MARCOX_AI.ANALYSIS.CLOSE')"
            @click="dialog.close()"
          />
        </div>
      </header>
      <div class="flex flex-wrap items-center gap-3">
        <div class="min-w-0 flex-1 basis-48">
          <AiSelect
            :model-value="assistantId || ''"
            :options="options"
            :label="t('MARCOX_AI.CONVERSATION.SELECT_AGENT')"
            :teleport="false"
            :disabled="working || processing"
            @update:model-value="selectAssistant"
          />
        </div>
        <span
          class="inline-flex items-center gap-2 rounded-lg border px-3 py-2 text-xs font-medium"
          :class="
            active
              ? 'border-n-teal-6 bg-n-teal-2 text-n-teal-11'
              : 'border-n-weak bg-n-alpha-1 text-n-slate-11'
          "
          ><span class="size-1.5 rounded-full bg-current" />{{
            t(active ? 'MARCOX_AI.PANEL.ACTIVE' : 'MARCOX_AI.PANEL.PAUSED')
          }}</span
        >
        <Button
          type="button"
          variant="outline"
          :icon="active ? 'i-lucide-pause' : 'i-lucide-play'"
          color="slate"
          :label="
            t(
              active ? 'MARCOX_AI.PANEL.PAUSE' : 'MARCOX_AI.CONVERSATION.RESUME'
            )
          "
          :disabled="working || processing || !available"
          @click="act(active ? 'pause' : 'resume')"
        />
      </div>
      <div class="grid gap-2 sm:grid-cols-2">
        <Button
          icon="i-lucide-sparkles"
          :label="t('MARCOX_AI.PANEL.PREPARE')"
          class="!h-11"
          :disabled="working || processing || state?.processing || !available"
          @click="replyReview.open('reply_review')"
        />
        <Button
          icon="i-lucide-file-search"
          variant="outline"
          color="slate"
          class="!h-11"
          :label="t('MARCOX_AI.PANEL.ANALYZE')"
          :is-loading="working || processing"
          :disabled="working || processing || !available"
          @click="analyze"
        />
      </div>
      <div
        class="flex flex-wrap items-center justify-between gap-2 pb-2 text-xs text-n-slate-11"
      >
        <span>{{ t('MARCOX_AI.PANEL.REVIEW') }}</span
        ><span class="inline-flex items-center gap-1.5"
          ><span
            :class="globalScope ? 'i-lucide-globe' : 'i-lucide-message-circle'"
            class="size-3.5 shrink-0"
          />{{
            t(
              globalScope
                ? 'MARCOX_AI.PANEL.SCOPE_GLOBAL'
                : 'MARCOX_AI.PANEL.SCOPE_CONVERSATION'
            )
          }}</span
        >
      </div>
      <p v-if="!assistants.length" class="text-sm text-n-slate-11">
        {{ t('MARCOX_AI.CONVERSATION.NO_AGENT') }}
      </p>
      <p
        v-if="state?.status === 'awaiting_human'"
        class="rounded-lg bg-n-amber-2 p-3 text-sm text-n-amber-11"
      >
        {{ t('MARCOX_AI.AUTOMATION.AWAITING_HUMAN') }}
      </p>
      <p v-if="selected && !selected.available" class="text-sm text-n-amber-11">
        {{ t('MARCOX_AI.EDITOR.CONNECTION_REQUIRED') }}
      </p>
      <AiPanelSection
        :title="t('MARCOX_AI.PANEL.CONTROLS')"
        icon="i-lucide-settings"
        :hint="
          messagesLimit === null
            ? t('MARCOX_AI.ANALYSIS.CONTEXT_ALL', { count: totalMessages })
            : t('MARCOX_AI.ANALYSIS.CONTEXT_RECENT', {
                count: selectedMessages,
              })
        "
      >
        <template v-if="isAdmin && state?.id" #trailing>
          <AiToggleRow
            :model-value="state.automatic_handoff_enabled ?? true"
            class="!py-0"
            :label="t('MARCOX_AI.PANEL.AUTO_PAUSE')"
            :disabled="working || processing"
            @update:model-value="setAutoPause"
          />
        </template>
        <div v-if="totalMessages" class="space-y-2">
          <label
            :for="`ai-context-${chat.id}`"
            class="flex max-w-sm items-center justify-between gap-3 text-xs font-medium text-n-slate-12"
          >
            <span>{{ t('MARCOX_AI.ANALYSIS.CONTEXT_LABEL') }}</span>
            <span class="text-n-slate-11">
              {{
                messagesLimit === null
                  ? t('MARCOX_AI.ANALYSIS.CONTEXT_ALL', {
                      count: totalMessages,
                    })
                  : t('MARCOX_AI.ANALYSIS.CONTEXT_RECENT', {
                      count: selectedMessages,
                    })
              }}
            </span>
          </label>
          <input
            :id="`ai-context-${chat.id}`"
            type="range"
            min="1"
            :max="totalMessages"
            :value="selectedMessages"
            :disabled="working || processing"
            class="reset-base !mb-0 !h-4 w-full max-w-sm cursor-pointer accent-n-blue-9"
            @input="selectContext"
          />
          <p class="m-0 text-xs leading-5 text-n-slate-11">
            {{ t('MARCOX_AI.ANALYSIS.CONTEXT_HINT') }}
          </p>
          <p
            v-if="contextChanged && analysis.status === 'ready'"
            class="text-xs text-n-amber-11"
          >
            {{ t('MARCOX_AI.ANALYSIS.CONTEXT_CHANGED') }}
          </p>
        </div>
        <p class="mb-0 mt-2 text-xs leading-5 text-n-slate-11">
          {{ t('MARCOX_AI.CONVERSATION.AUTO_PAUSE_HINT') }}
        </p>
      </AiPanelSection>
      <AiPanelSection
        v-if="isAdmin && assistantId"
        :title="t('MARCOX_AI.PANEL.SHORTCUTS')"
        icon="i-lucide-link"
        expanded
        accent
      >
        <div class="grid gap-3 sm:grid-cols-3">
          <article class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2">
            <div class="flex items-center gap-3 p-3">
              <span
                class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-blue-3 text-n-blue-11"
                ><span class="i-lucide-file size-5"
              /></span>
              <div class="min-w-0">
                <h4 class="m-0 text-sm font-semibold text-n-slate-12">
                  {{ t('MARCOX_AI.RESOURCES.TITLE') }}
                </h4>
                <p class="mb-0 mt-1 text-xs text-n-slate-11">
                  {{
                    shortcutCounts.resources === null
                      ? '—'
                      : t('MARCOX_AI.RESOURCES.COUNT', {
                          count: shortcutCounts.resources,
                        })
                  }}
                </p>
              </div>
            </div>
            <Button
              variant="ghost"
              icon="i-lucide-plus"
              class="w-full !rounded-t-none !border-t !border-n-weak"
              :label="t('MARCOX_AI.PANEL.ADD')"
              :disabled="working"
              @click="openQuick('resources')"
            />
          </article>
          <article class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2">
            <div class="flex items-center gap-3 p-3">
              <span
                class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-teal-3 text-n-teal-11"
                ><PixIcon class="size-6"
              /></span>
              <div class="min-w-0">
                <h4 class="m-0 text-sm font-semibold text-n-slate-12">
                  {{ t('MARCOX_AI.PIX.TITLE') }}
                </h4>
                <p class="mb-0 mt-1 text-xs text-n-slate-11">
                  {{
                    shortcutCounts.pix === null
                      ? '—'
                      : t('MARCOX_AI.PIX.ACTIVE_COUNT', {
                          count: shortcutCounts.pix,
                        })
                  }}
                </p>
              </div>
            </div>
            <Button
              variant="ghost"
              icon="i-lucide-plus"
              class="w-full !rounded-t-none !border-t !border-n-weak"
              :label="t('MARCOX_AI.PANEL.REGISTER')"
              :disabled="working"
              @click="openQuick('pix')"
            />
          </article>
          <article class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2">
            <div class="flex items-center gap-3 p-3">
              <span
                class="flex size-10 shrink-0 items-center justify-center rounded-full bg-n-ruby-3 text-n-ruby-11"
                ><span class="i-lucide-bell size-5"
              /></span>
              <div class="min-w-0">
                <h4 class="m-0 text-sm font-semibold text-n-slate-12">
                  {{ t('MARCOX_AI.PANEL.NOTICES') }}
                </h4>
                <p class="mb-0 mt-1 text-xs text-n-slate-11">
                  {{
                    shortcutCounts.notices === null
                      ? '—'
                      : t('MARCOX_AI.PANEL.NUMBERS', {
                          count: shortcutCounts.notices,
                        })
                  }}
                </p>
              </div>
            </div>
            <Button
              variant="ghost"
              icon="i-lucide-plus"
              class="w-full !rounded-t-none !border-t !border-n-weak"
              :label="t('MARCOX_AI.PANEL.REGISTER')"
              :disabled="working"
              @click="openQuick('notices')"
            />
          </article>
        </div>
        <p
          class="mb-0 mt-3 flex items-start gap-2 text-xs leading-5 text-n-slate-11"
        >
          <span class="i-lucide-info mt-0.5 size-4 shrink-0" />{{
            t(
              globalScope
                ? 'MARCOX_AI.PANEL.ADD_GLOBAL'
                : 'MARCOX_AI.PANEL.ADD_CONVERSATION'
            )
          }}
        </p>
        <p
          v-if="shortcutError"
          role="alert"
          class="mb-0 mt-2 text-xs text-n-ruby-11"
        >
          {{ t('MARCOX_AI.PANEL.LOAD_ERROR') }}
        </p>
      </AiPanelSection>
      <AiPanelSection
        v-if="visible && state?.id"
        :title="t('MARCOX_AI.PANEL.MEMORY')"
        icon="i-lucide-database"
      >
        <template #trailing>
          <span class="text-xs text-n-blue-11">{{
            t('MARCOX_AI.PANEL.VIEW_CONTEXT')
          }}</span>
        </template>
        <ConversationMemory
          :conversation-id="chat.id"
          embedded
          @updated="fetchReport"
        />
      </AiPanelSection>
      <AiPanelSection
        v-if="visible && state?.id"
        :title="t('MARCOX_AI.PANEL.PENDING')"
        icon="i-lucide-clipboard-list"
      >
        <template #trailing>
          <span
            class="rounded-full px-2 py-1 text-xs"
            :class="
              pendingCount
                ? 'bg-n-amber-3 text-n-amber-11'
                : 'bg-n-alpha-2 text-n-slate-11'
            "
            >{{
              t('MARCOX_AI.PANEL.OPEN_COUNT', { count: pendingCount })
            }}</span
          >
        </template>
        <AgentAlertList
          :conversation-id="chat.id"
          embedded
          @loaded="pendingCount = $event"
        />
      </AiPanelSection>
      <p
        v-if="processing"
        class="flex items-center gap-2 text-sm text-n-slate-11"
      >
        <span class="i-lucide-loader-circle size-4 animate-spin" />{{
          t('MARCOX_AI.ANALYSIS.PROCESSING')
        }}
      </p>
      <p
        v-if="['outdated', 'failed', 'sent'].includes(analysis.status)"
        class="rounded-lg bg-n-alpha-1 p-3 text-sm text-n-slate-11"
      >
        {{ t(`MARCOX_AI.ANALYSIS.${analysis.status.toUpperCase()}`) }}
      </p>
      <div
        v-if="analysis.status === 'ready'"
        class="max-h-[40vh] space-y-4 overflow-y-auto pe-2"
      >
        <p class="text-xs text-n-slate-10">
          {{
            t('MARCOX_AI.ANALYSIS.COUNT', { count: analysis.messages_count })
          }}
        </p>
        <div class="rounded-lg border border-n-weak p-4">
          <h4 class="m-0 text-xs font-semibold text-n-slate-12">
            {{ t('MARCOX_AI.ANALYSIS.SUMMARY') }}
          </h4>
          <p
            class="mb-0 mt-2 whitespace-pre-line text-sm leading-6 text-n-slate-11"
          >
            {{ analysis.summary }}
          </p>
          <h4 class="mb-0 mt-4 text-xs font-semibold text-n-slate-12">
            {{ t('MARCOX_AI.ANALYSIS.NEXT_STEP') }}
          </h4>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ analysis.next_step }}
          </p>
        </div>
        <h4 class="text-sm font-semibold text-n-slate-12">
          {{ t('MARCOX_AI.ANALYSIS.DRAFT') }}
        </h4>
        <label v-for="(_, index) in parts" :key="index" class="block">
          <span class="mb-2 block text-xs text-n-slate-11">{{
            t('MARCOX_AI.ANALYSIS.PART', { number: index + 1 })
          }}</span>
          <textarea
            v-model="parts[index]"
            rows="3"
            class="reset-base !mb-0 w-full resize-y rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm text-n-slate-12"
          />
        </label>
        <p v-if="analysis.plan.reaction" class="text-sm text-n-slate-11">
          {{
            t('MARCOX_AI.PLAYGROUND.REACTION', {
              emoji: analysis.plan.reaction,
            })
          }}
        </p>
        <p v-if="analysis.plan.handoff" class="text-sm text-n-amber-11">
          {{
            t('MARCOX_AI.PLAYGROUND.HANDOFF', {
              reason: analysis.plan.handoff_reason,
            })
          }}
        </p>
      </div>
    </div>
    <template #footer>
      <div
        class="flex flex-wrap items-center justify-end gap-3 border-t border-n-weak pt-4"
      >
        <Button
          type="button"
          variant="outline"
          color="blue"
          icon="i-lucide-user-round"
          :label="t('MARCOX_AI.CONVERSATION.HUMAN')"
          :disabled="working || !state?.assistant_id"
          @click="act('handoff')"
        />
        <div class="flex items-center gap-2">
          <Button
            type="button"
            variant="faded"
            color="slate"
            icon="i-lucide-x"
            :label="t('MARCOX_AI.ANALYSIS.CLOSE')"
            @click="dialog.close()"
          />
          <Button
            v-if="analysis.status === 'ready'"
            type="button"
            icon="i-lucide-send"
            :label="t('MARCOX_AI.ANALYSIS.SEND')"
            :disabled="working || !available || !hasResponse || contextChanged"
            :is-loading="working"
            @click="send"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>
