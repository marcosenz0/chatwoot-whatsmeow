<script setup>
import { computed, ref, toRaw } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDistanceToNow } from 'date-fns';
import { enUS, es, pt, ptBR } from 'date-fns/locale';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import FlowEditor from './FlowEditor.vue';
import StudioSearchInput from './StudioSearchInput.vue';
import StudioSelect from './StudioSelect.vue';
import { whatsappCloudAutomationsAPI } from 'dashboard/api/whatsappCloudStudio';

const props = defineProps({
  inbox: { type: Object, required: true },
  templates: { type: Array, default: () => [] },
  automations: { type: Array, default: () => [] },
});

const emit = defineEmits(['update']);
const { t, locale } = useI18n();

const editingFlow = ref(null);
const isSaving = ref(false);
const isPublishing = ref(false);
const search = ref('');
const statusFilter = ref('all');

const cloneFlow = flow => JSON.parse(JSON.stringify(toRaw(flow)));

const flowErrorMessage = (error, fallbackKey) => {
  const responseError =
    error?.response?.data?.error ||
    error?.response?.data?.message ||
    error?.response?.data?.errors;
  const details = (
    Array.isArray(responseError) ? responseError.join(' ') : responseError || ''
  ).toLowerCase();

  if (details.includes('keyword')) {
    return t('WHATSAPP_CLOUD_STUDIO.FLOWS.VALIDATION.KEYWORD');
  }
  if (
    ['connection', 'unreachable', 'cycle', 'edge'].some(term =>
      details.includes(term)
    )
  ) {
    return t('WHATSAPP_CLOUD_STUDIO.FLOWS.VALIDATION.CONNECTIONS');
  }
  if (details.includes('template')) {
    return t('WHATSAPP_CLOUD_STUDIO.FLOWS.VALIDATION.TEMPLATE');
  }
  if (
    ['message', 'node', 'button', 'condition', 'action', 'wait'].some(term =>
      details.includes(term)
    )
  ) {
    return t('WHATSAPP_CLOUD_STUDIO.FLOWS.VALIDATION.NODE');
  }
  return fallbackKey === 'WHATSAPP_CLOUD_STUDIO.FLOWS.PUBLISH_ERROR'
    ? t('WHATSAPP_CLOUD_STUDIO.FLOWS.PUBLISH_ERROR')
    : t('WHATSAPP_CLOUD_STUDIO.FLOWS.SAVE_ERROR');
};

const dateLocale = computed(() => {
  const locales = { pt_BR: ptBR, pt, es, en: enUS };
  return locales[locale.value] || enUS;
});

const filteredAutomations = computed(() => {
  const term = search.value.toLowerCase().trim();
  return props.automations.filter(flow => {
    const matchesSearch =
      !term ||
      flow.name.toLowerCase().includes(term) ||
      flow.description?.toLowerCase().includes(term);
    const matchesStatus =
      statusFilter.value === 'all' || flow.status === statusFilter.value;
    return matchesSearch && matchesStatus;
  });
});

const newFlow = () => {
  const triggerId = `trigger_${Date.now()}`;
  const messageId = `message_${Date.now()}`;
  const endId = `end_${Date.now()}`;
  editingFlow.value = {
    id: null,
    inbox_id: props.inbox.id,
    name: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NEW_FLOW_NAME'),
    description: '',
    status: 'draft',
    trigger_type: 'keyword',
    trigger_config: { keywords: [] },
    definition: {
      nodes: [
        {
          id: triggerId,
          type: 'trigger',
          position: { x: 80, y: 220 },
          config: {},
        },
        {
          id: messageId,
          type: 'message',
          position: { x: 420, y: 220 },
          config: {
            mode: 'session',
            text: '',
            buttons: [],
            processed_params: {},
          },
        },
        {
          id: endId,
          type: 'end',
          position: { x: 760, y: 220 },
          config: {},
        },
      ],
      edges: [
        {
          id: `edge_${triggerId}`,
          source: triggerId,
          target: messageId,
          source_handle: 'default',
        },
        {
          id: `edge_${messageId}`,
          source: messageId,
          target: endId,
          source_handle: 'default',
        },
      ],
    },
  };
};

const editFlow = flow => {
  editingFlow.value = cloneFlow(flow);
};

const refresh = async () => {
  const response = await whatsappCloudAutomationsAPI.getForInbox(
    props.inbox.id
  );
  emit('update', response.data);
  return response.data;
};

const persistFlow = async payload => {
  const response = editingFlow.value.id
    ? await whatsappCloudAutomationsAPI.update(editingFlow.value.id, {
        automation: payload,
      })
    : await whatsappCloudAutomationsAPI.create({ automation: payload });
  editingFlow.value = response.data;
  await refresh();
  return response.data;
};

const saveFlow = async payload => {
  if (isSaving.value || isPublishing.value) return;
  isSaving.value = true;
  try {
    await persistFlow(payload);
    useAlert(t('WHATSAPP_CLOUD_STUDIO.FLOWS.SAVED'));
  } catch (error) {
    useAlert(flowErrorMessage(error, 'WHATSAPP_CLOUD_STUDIO.FLOWS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const publishFlow = async payload => {
  if (isSaving.value || isPublishing.value) return;
  isPublishing.value = true;
  try {
    const savedFlow = await persistFlow(payload);
    const response = await whatsappCloudAutomationsAPI.publish(savedFlow.id);
    editingFlow.value = response.data;
    await refresh();
    useAlert(t('WHATSAPP_CLOUD_STUDIO.FLOWS.PUBLISHED'));
  } catch (error) {
    useAlert(
      flowErrorMessage(error, 'WHATSAPP_CLOUD_STUDIO.FLOWS.PUBLISH_ERROR')
    );
  } finally {
    isPublishing.value = false;
  }
};

const toggleFlow = async flow => {
  try {
    if (flow.status === 'active') {
      await whatsappCloudAutomationsAPI.pause(flow.id);
    } else {
      await whatsappCloudAutomationsAPI.publish(flow.id);
    }
    await refresh();
  } catch {
    useAlert(t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS_ERROR'));
  }
};

const deleteFlow = async flow => {
  if (
    // eslint-disable-next-line no-alert
    !window.confirm(
      t('WHATSAPP_CLOUD_STUDIO.FLOWS.DELETE_CONFIRM', { name: flow.name })
    )
  ) {
    return;
  }
  try {
    await whatsappCloudAutomationsAPI.delete(flow.id);
    await refresh();
    useAlert(t('WHATSAPP_CLOUD_STUDIO.FLOWS.DELETED'));
  } catch (error) {
    useAlert(t('WHATSAPP_CLOUD_STUDIO.FLOWS.DELETE_ERROR'));
  }
};

const statusTone = status => {
  if (status === 'active') return 'bg-n-teal-3 text-n-teal-11';
  if (status === 'paused') return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-slate-3 text-n-slate-11';
};

const statusLabel = status => {
  const labels = {
    draft: t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.DRAFT'),
    active: t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.ACTIVE'),
    paused: t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.PAUSED'),
  };
  return labels[status];
};

const relativeTime = value =>
  formatDistanceToNow(new Date(value), {
    addSuffix: true,
    locale: dateLocale.value,
  });
</script>

<template>
  <section>
    <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="text-xl font-semibold text-n-slate-12">
          {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.TITLE') }}
        </h2>
        <p class="mt-1 max-w-3xl text-sm text-n-slate-11">
          {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.DESCRIPTION') }}
        </p>
      </div>
      <Button
        :label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.NEW')"
        icon="i-lucide-plus"
        @click="newFlow"
      />
    </div>

    <div class="mb-4 grid gap-3 sm:grid-cols-[minmax(0,1fr)_12rem]">
      <StudioSearchInput
        v-model="search"
        :label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.SEARCH_LABEL')"
        :placeholder="t('WHATSAPP_CLOUD_STUDIO.FLOWS.SEARCH')"
      />
      <label class="min-w-0">
        <span class="sr-only">
          {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS_LABEL') }}
        </span>
        <StudioSelect
          v-model="statusFilter"
          :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS_LABEL')"
        >
          <option value="all">
            {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.ALL') }}
          </option>
          <option value="active">
            {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.ACTIVE') }}
          </option>
          <option value="draft">
            {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.DRAFT') }}
          </option>
          <option value="paused">
            {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.PAUSED') }}
          </option>
        </StudioSelect>
      </label>
    </div>

    <div
      v-if="filteredAutomations.length === 0"
      class="flex min-h-72 flex-col items-center justify-center rounded-2xl border border-dashed border-n-strong bg-n-alpha-1 p-8 text-center"
    >
      <span
        class="i-lucide-workflow mb-3 size-9 text-n-slate-9"
        aria-hidden="true"
      />
      <h3 class="text-base font-semibold text-n-slate-12">
        {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EMPTY_TITLE') }}
      </h3>
      <p class="mt-1 max-w-lg text-sm text-n-slate-10">
        {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EMPTY_DESCRIPTION') }}
      </p>
      <Button
        class="mt-5"
        :label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.CREATE_FIRST')"
        icon="i-lucide-plus"
        @click="newFlow"
      />
    </div>

    <div v-else class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      <article
        v-for="flow in filteredAutomations"
        :key="flow.id"
        class="flex min-h-56 flex-col rounded-2xl border border-n-weak bg-n-alpha-1 p-5 transition hover:border-n-strong hover:bg-n-alpha-2"
      >
        <div class="flex items-start justify-between gap-3">
          <span
            class="flex size-10 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
          >
            <span class="i-lucide-workflow size-5" aria-hidden="true" />
          </span>
          <span
            class="rounded-full px-2 py-1 text-xs font-medium"
            :class="statusTone(flow.status)"
          >
            {{ statusLabel(flow.status) }}
          </span>
        </div>
        <h3 class="mt-4 truncate text-base font-semibold text-n-slate-12">
          {{ flow.name }}
        </h3>
        <p class="mt-1 line-clamp-2 min-h-10 text-sm text-n-slate-10">
          {{
            flow.description || t('WHATSAPP_CLOUD_STUDIO.FLOWS.NO_DESCRIPTION')
          }}
        </p>
        <div class="mt-4 grid grid-cols-3 gap-2 text-center">
          <div class="rounded-lg bg-n-alpha-2 p-2">
            <div class="text-sm font-semibold text-n-slate-12">
              {{ flow.run_summary?.total || 0 }}
            </div>
            <div class="text-[0.65rem] text-n-slate-9">
              {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.RUNS') }}
            </div>
          </div>
          <div class="rounded-lg bg-n-alpha-2 p-2">
            <div class="text-sm font-semibold text-n-teal-11">
              {{ flow.run_summary?.completed || 0 }}
            </div>
            <div class="text-[0.65rem] text-n-slate-9">
              {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.COMPLETED') }}
            </div>
          </div>
          <div class="rounded-lg bg-n-alpha-2 p-2">
            <div class="text-sm font-semibold text-n-ruby-11">
              {{ flow.run_summary?.failed || 0 }}
            </div>
            <div class="text-[0.65rem] text-n-slate-9">
              {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.FAILED') }}
            </div>
          </div>
        </div>
        <div
          class="mt-auto flex items-center justify-between border-t border-n-weak pt-4"
        >
          <span class="text-xs text-n-slate-9">
            {{
              t('WHATSAPP_CLOUD_STUDIO.FLOWS.UPDATED', {
                time: relativeTime(flow.updated_at),
              })
            }}
          </span>
          <div class="flex items-center gap-1">
            <button
              type="button"
              class="flex size-9 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-3 hover:text-n-slate-12"
              :aria-label="
                flow.status === 'active'
                  ? t('WHATSAPP_CLOUD_STUDIO.FLOWS.PAUSE')
                  : t('WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIVATE')
              "
              @click="toggleFlow(flow)"
            >
              <span
                class="size-4"
                :class="
                  flow.status === 'active' ? 'i-lucide-pause' : 'i-lucide-play'
                "
                aria-hidden="true"
              />
            </button>
            <button
              type="button"
              class="flex size-9 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-3 hover:text-n-blue-11"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDIT')"
              @click="editFlow(flow)"
            >
              <span class="i-lucide-pencil size-4" aria-hidden="true" />
            </button>
            <button
              type="button"
              class="flex size-9 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-ruby-3 hover:text-n-ruby-11"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.DELETE')"
              @click="deleteFlow(flow)"
            >
              <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
            </button>
          </div>
        </div>
      </article>
    </div>

    <FlowEditor
      v-if="editingFlow"
      :flow="editingFlow"
      :templates="templates"
      :is-saving="isSaving"
      :is-publishing="isPublishing"
      @close="editingFlow = null"
      @save="saveFlow"
      @publish="publishFlow"
    />
  </section>
</template>
