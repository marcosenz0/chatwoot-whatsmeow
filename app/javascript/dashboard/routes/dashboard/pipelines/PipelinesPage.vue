<script setup>
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Draggable from 'vuedraggable';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const BOARD_PER_PAGE = 50;
const CANDIDATES_PER_PAGE = 20;
const DEFAULT_COLOR = '#2563eb';
const OPEN_STATUS = 'open';
const ALL_STATUS = 'all';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const pipelines = useMapGetter('pipelines/getPipelines');
const board = useMapGetter('pipelines/getBoard');
const uiFlags = useMapGetter('pipelines/getUIFlags');

const selectedPipelineId = ref(null);
const pipelineDialogRef = ref(null);
const stageDialogRef = ref(null);
const deletePipelineDialogRef = ref(null);
const deleteStageDialogRef = ref(null);
const candidateDialogRef = ref(null);
const editingPipeline = ref(null);
const editingStage = ref(null);
const stageToDelete = ref(null);
const isBootstrapping = ref(true);
const isCandidateDialogOpen = ref(false);
const addingConversationId = ref(null);
const removingConversationId = ref(null);
const stagePages = reactive({});

const boardFilters = reactive({
  q: '',
  status: ALL_STATUS,
  includeGroups: false,
});

const candidateFilters = reactive({
  q: '',
  status: OPEN_STATUS,
  includeGroups: false,
  stageId: null,
});

const candidateResults = ref([]);
const candidateMeta = ref({
  current_page: 1,
  count: 0,
  next_page: null,
});

const pipelineForm = reactive({
  name: '',
  description: '',
  color: DEFAULT_COLOR,
});

const stageForm = reactive({
  name: '',
  color: DEFAULT_COLOR,
  category: OPEN_STATUS,
  probability: 10,
  stale_after_days: 3,
});

let boardSearchTimer = null;
let candidateSearchTimer = null;

const selectedPipeline = computed(() =>
  pipelines.value.find(
    pipeline => pipeline.id === Number(selectedPipelineId.value)
  )
);

const stages = computed(() => board.value?.stages || []);
const hasPipelines = computed(() => pipelines.value.length > 0);
const hasStages = computed(() => stages.value.length > 0);
const isBoardLoading = computed(
  () => uiFlags.value.isFetching || uiFlags.value.isFetchingBoard
);
const isInitialBoardLoading = computed(
  () => isBoardLoading.value && !board.value
);
const isRefreshingBoard = computed(() => isBoardLoading.value && board.value);
const isCandidateLoading = computed(() => uiFlags.value.isFetchingCandidates);

const statusOptions = computed(() => [
  { value: ALL_STATUS, label: t('PIPELINES.FILTERS.STATUS_OPTIONS.ALL') },
  { value: OPEN_STATUS, label: t('PIPELINES.FILTERS.STATUS_OPTIONS.OPEN') },
  { value: 'pending', label: t('PIPELINES.FILTERS.STATUS_OPTIONS.PENDING') },
  { value: 'snoozed', label: t('PIPELINES.FILTERS.STATUS_OPTIONS.SNOOZED') },
  { value: 'resolved', label: t('PIPELINES.FILTERS.STATUS_OPTIONS.RESOLVED') },
]);

const candidateStatusOptions = computed(() =>
  statusOptions.value.filter(option => option.value !== ALL_STATUS)
);

const stageOptions = computed(() =>
  stages.value.map(stage => ({ id: stage.id, name: stage.name }))
);

const boardParams = computed(() => ({
  per_page: BOARD_PER_PAGE,
  stage_pages: JSON.stringify(stagePages),
  q: boardFilters.q,
  status: boardFilters.status,
  include_groups: boardFilters.includeGroups,
}));

const resetStagePages = () => {
  Object.keys(stagePages).forEach(key => {
    delete stagePages[key];
  });
};

const fetchBoard = async () => {
  if (!selectedPipelineId.value) return null;
  return store.dispatch('pipelines/getBoard', {
    id: selectedPipelineId.value,
    params: boardParams.value,
  });
};

const fetchPipelines = async () => {
  const records = await store.dispatch('pipelines/get');
  if (!records.length) {
    selectedPipelineId.value = null;
    return records;
  }

  const selectedExists = records.some(
    pipeline => pipeline.id === Number(selectedPipelineId.value)
  );
  if (!selectedPipelineId.value || !selectedExists) {
    selectedPipelineId.value = records[0].id;
  }
  return records;
};

const scheduleBoardRefresh = () => {
  resetStagePages();
  window.clearTimeout(boardSearchTimer);
  boardSearchTimer = window.setTimeout(fetchBoard, 300);
};

const openNewPipelineDialog = () => {
  editingPipeline.value = null;
  Object.assign(pipelineForm, {
    name: '',
    description: '',
    color: DEFAULT_COLOR,
  });
  pipelineDialogRef.value?.open();
};

const openEditPipelineDialog = () => {
  editingPipeline.value = selectedPipeline.value;
  Object.assign(pipelineForm, {
    name: selectedPipeline.value?.name || '',
    description: selectedPipeline.value?.description || '',
    color: selectedPipeline.value?.color || DEFAULT_COLOR,
  });
  pipelineDialogRef.value?.open();
};

const savePipeline = async () => {
  const payload = {
    pipeline: {
      name: pipelineForm.name,
      description: pipelineForm.description,
      color: pipelineForm.color,
    },
  };
  const action = editingPipeline.value
    ? store.dispatch('pipelines/update', {
        id: editingPipeline.value.id,
        ...payload,
      })
    : store.dispatch('pipelines/create', payload);

  const pipeline = await action;
  pipelineDialogRef.value?.close();
  selectedPipelineId.value = pipeline.id;
  await fetchPipelines();
  await fetchBoard();
  useAlert(t('PIPELINES.ALERTS.PIPELINE_SAVED'));
};

const requestDeletePipeline = () => {
  deletePipelineDialogRef.value?.open();
};

const confirmDeletePipeline = async () => {
  await store.dispatch('pipelines/delete', selectedPipelineId.value);
  deletePipelineDialogRef.value?.close();
  selectedPipelineId.value = null;
  resetStagePages();
  await fetchPipelines();
  await fetchBoard();
  useAlert(t('PIPELINES.ALERTS.PIPELINE_DELETED'));
};

const openNewStageDialog = () => {
  editingStage.value = null;
  Object.assign(stageForm, {
    name: '',
    color: DEFAULT_COLOR,
    category: OPEN_STATUS,
    probability: 10,
    stale_after_days: 3,
  });
  stageDialogRef.value?.open();
};

const openEditStageDialog = stage => {
  editingStage.value = stage;
  Object.assign(stageForm, {
    name: stage.name,
    color: stage.color || DEFAULT_COLOR,
    category: stage.category || OPEN_STATUS,
    probability: stage.probability ?? 10,
    stale_after_days: stage.stale_after_days ?? 3,
  });
  stageDialogRef.value?.open();
};

const saveStage = async () => {
  const payload = {
    pipelineId: selectedPipelineId.value,
    stage: {
      name: stageForm.name,
      color: stageForm.color,
      category: stageForm.category,
      probability: stageForm.probability,
      stale_after_days: stageForm.stale_after_days || null,
    },
  };

  if (editingStage.value) {
    await store.dispatch('pipelines/updateStage', {
      ...payload,
      stageId: editingStage.value.id,
    });
  } else {
    await store.dispatch('pipelines/createStage', payload);
  }

  stageDialogRef.value?.close();
  await fetchBoard();
  useAlert(t('PIPELINES.ALERTS.STAGE_SAVED'));
};

const requestDeleteStage = stage => {
  stageToDelete.value = stage;
  deleteStageDialogRef.value?.open();
};

const confirmDeleteStage = async () => {
  if (!stageToDelete.value) return;

  await store.dispatch('pipelines/deleteStage', {
    pipelineId: selectedPipelineId.value,
    stageId: stageToDelete.value.id,
  });
  deleteStageDialogRef.value?.close();
  stageToDelete.value = null;
  await fetchBoard();
  useAlert(t('PIPELINES.ALERTS.STAGE_DELETED'));
};

const loadMore = async stage => {
  stagePages[stage.id] = stage.pagination.next_page;
  await fetchBoard();
};

const openConversation = conversation => {
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: conversation.account_id,
      conversation_id: conversation.id,
    },
  });
};

const onConversationMoved = async (event, stage) => {
  const movedConversation = event.added?.element;
  if (!movedConversation) return;

  await store.dispatch('pipelines/moveConversation', {
    conversationId: movedConversation.id,
    pipelineStageId: stage.id,
  });
  await fetchBoard();
  useAlert(t('PIPELINES.ALERTS.CONVERSATION_MOVED'));
};

const removeConversation = async conversation => {
  removingConversationId.value = conversation.id;
  try {
    await store.dispatch('pipelines/removeConversation', {
      conversationId: conversation.id,
    });
    await fetchBoard();
    useAlert(t('PIPELINES.ALERTS.CONVERSATION_REMOVED'));
  } finally {
    removingConversationId.value = null;
  }
};

const candidateParams = page => ({
  page,
  per_page: CANDIDATES_PER_PAGE,
  q: candidateFilters.q,
  status: candidateFilters.status,
  include_groups: candidateFilters.includeGroups,
});

const fetchCandidates = async ({ page = 1, append = false } = {}) => {
  if (!selectedPipelineId.value) return;

  const payload = await store.dispatch('pipelines/getCandidates', {
    id: selectedPipelineId.value,
    params: candidateParams(page),
  });

  candidateResults.value = append
    ? [...candidateResults.value, ...payload.conversations]
    : payload.conversations;
  candidateMeta.value = payload.meta;
};

const openCandidatesDialog = stage => {
  const fallbackStage = stageOptions.value[0];
  candidateFilters.stageId = stage?.id || fallbackStage?.id || null;
  candidateFilters.q = '';
  candidateFilters.status = OPEN_STATUS;
  candidateFilters.includeGroups = false;
  candidateResults.value = [];
  candidateMeta.value = { current_page: 1, count: 0, next_page: null };
  isCandidateDialogOpen.value = true;
  candidateDialogRef.value?.open();
  fetchCandidates();
};

const closeCandidatesDialog = () => {
  isCandidateDialogOpen.value = false;
};

const scheduleCandidateRefresh = () => {
  if (!isCandidateDialogOpen.value) return;

  window.clearTimeout(candidateSearchTimer);
  candidateSearchTimer = window.setTimeout(() => fetchCandidates(), 300);
};

const addConversationToStage = async conversation => {
  if (!candidateFilters.stageId) return;

  addingConversationId.value = conversation.id;
  try {
    await store.dispatch('pipelines/moveConversation', {
      conversationId: conversation.id,
      pipelineStageId: candidateFilters.stageId,
    });
    candidateResults.value = candidateResults.value.filter(
      item => item.id !== conversation.id
    );
    candidateMeta.value = {
      ...candidateMeta.value,
      count: Math.max((candidateMeta.value.count || 1) - 1, 0),
    };
    await fetchBoard();
    useAlert(t('PIPELINES.ALERTS.CONVERSATION_ADDED'));
  } finally {
    addingConversationId.value = null;
  }
};

const loadMoreCandidates = () => {
  if (!candidateMeta.value.next_page) return;
  fetchCandidates({ page: candidateMeta.value.next_page, append: true });
};

const lastMessagePreview = conversation => {
  const content = conversation.messages?.[0]?.content;
  return content || t('PIPELINES.CARD.NO_MESSAGE');
};

const assigneeName = conversation => {
  return conversation.meta?.assignee?.name || t('PIPELINES.CARD.UNASSIGNED');
};

const senderName = conversation => {
  return conversation.meta?.sender?.name || t('PIPELINES.CARD.UNKNOWN_CONTACT');
};

const contactDetail = conversation => {
  const sender = conversation.meta?.sender || {};
  return (
    sender.phone_number ||
    sender.email ||
    sender.identifier ||
    t('PIPELINES.CARD.NO_CONTACT_DETAIL')
  );
};

const formatCount = count => t('PIPELINES.STAGE.COUNT', { count });

watch(selectedPipelineId, async () => {
  if (isBootstrapping.value) return;

  resetStagePages();
  await fetchBoard();
});

watch(
  () => [boardFilters.q, boardFilters.status, boardFilters.includeGroups],
  scheduleBoardRefresh
);

watch(
  () => [
    candidateFilters.q,
    candidateFilters.status,
    candidateFilters.includeGroups,
  ],
  scheduleCandidateRefresh
);

onMounted(async () => {
  await fetchPipelines();
  await fetchBoard();
  isBootstrapping.value = false;
});

onBeforeUnmount(() => {
  window.clearTimeout(boardSearchTimer);
  window.clearTimeout(candidateSearchTimer);
});
</script>

<template>
  <main class="flex h-full min-h-0 flex-col bg-n-background text-n-slate-12">
    <header
      class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-5 py-4"
    >
      <div class="flex min-w-0 flex-col">
        <div class="flex items-center gap-2">
          <span class="i-lucide-columns-3 size-5 text-n-blue-11" />
          <h1 class="m-0 text-base font-semibold text-n-slate-12">
            {{ t('PIPELINES.HEADER.TITLE') }}
          </h1>
        </div>
        <p class="m-0 mt-1 max-w-3xl text-sm text-n-slate-11">
          {{ t('PIPELINES.HEADER.DESCRIPTION') }}
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          v-tooltip.top="t('PIPELINES.HEADER.REFRESH')"
          icon="i-lucide-refresh-cw"
          slate
          sm
          :is-loading="isBoardLoading"
          :disabled="!selectedPipelineId"
          @click="fetchBoard"
        />
        <Button
          v-tooltip.top="t('PIPELINES.HEADER.EDIT_PIPELINE')"
          icon="i-lucide-settings-2"
          slate
          sm
          :disabled="!selectedPipeline"
          @click="openEditPipelineDialog"
        />
        <Button
          icon="i-lucide-plus"
          sm
          :label="t('PIPELINES.HEADER.NEW_PIPELINE')"
          @click="openNewPipelineDialog"
        />
      </div>
    </header>

    <section
      v-if="isInitialBoardLoading"
      class="flex flex-1 items-center justify-center gap-2 text-sm text-n-slate-11"
    >
      <Spinner class="size-5" />
      <span>{{ t('PIPELINES.LOADING') }}</span>
    </section>

    <section
      v-else-if="!hasPipelines"
      class="flex flex-1 items-center justify-center px-6 text-center"
    >
      <div class="flex max-w-md flex-col items-center gap-3">
        <span class="i-lucide-columns-3 size-8 text-n-blue-11" />
        <h2 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ t('PIPELINES.EMPTY.TITLE') }}
        </h2>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('PIPELINES.EMPTY.DESCRIPTION') }}
        </p>
        <Button
          icon="i-lucide-plus"
          :label="t('PIPELINES.HEADER.NEW_PIPELINE')"
          @click="openNewPipelineDialog"
        />
      </div>
    </section>

    <section v-else class="relative flex min-h-0 flex-1 flex-col">
      <div
        v-if="isRefreshingBoard"
        class="absolute right-5 top-3 z-10 flex items-center gap-2 rounded-lg bg-n-alpha-3 px-3 py-2 text-xs text-n-slate-11 shadow-sm backdrop-blur"
      >
        <Spinner class="size-4" />
        <span>{{ t('PIPELINES.REFRESHING') }}</span>
      </div>

      <div
        class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-5 py-3"
      >
        <div class="flex min-w-0 flex-wrap items-center gap-2">
          <select
            v-model="selectedPipelineId"
            class="reset-base h-9 min-w-[14rem] rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
          >
            <option
              v-for="pipeline in pipelines"
              :key="pipeline.id"
              :value="pipeline.id"
            >
              {{ pipeline.name }}
            </option>
          </select>
          <span
            class="size-3 rounded-sm border border-n-weak"
            :style="{ backgroundColor: selectedPipeline?.color }"
          />
          <span class="text-xs text-n-slate-10">
            {{
              t('PIPELINES.HEADER.TOTAL', { count: board?.total_count || 0 })
            }}
          </span>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <Button
            icon="i-lucide-user-plus"
            teal
            sm
            :label="t('PIPELINES.HEADER.ADD_CONVERSATION')"
            :disabled="!hasStages"
            @click="openCandidatesDialog()"
          />
          <Button
            v-tooltip.top="t('PIPELINES.HEADER.DELETE_PIPELINE')"
            icon="i-lucide-trash"
            ruby
            faded
            sm
            :disabled="pipelines.length < 2"
            @click="requestDeletePipeline"
          />
          <Button
            icon="i-lucide-plus"
            slate
            sm
            :label="t('PIPELINES.HEADER.NEW_STAGE')"
            @click="openNewStageDialog"
          />
        </div>
      </div>

      <div
        class="flex flex-wrap items-center gap-3 border-b border-n-weak px-5 py-3"
      >
        <Input
          v-model="boardFilters.q"
          size="sm"
          class="min-w-[15rem] flex-1"
          :placeholder="t('PIPELINES.FILTERS.SEARCH_PLACEHOLDER')"
        />
        <select
          v-model="boardFilters.status"
          class="reset-base h-8 min-w-[10rem] rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
          :aria-label="t('PIPELINES.FILTERS.STATUS')"
        >
          <option
            v-for="option in statusOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
        <label
          class="flex h-8 items-center gap-2 rounded-lg bg-n-alpha-black2 px-3 text-sm text-n-slate-11 outline outline-1 outline-n-weak"
        >
          <input
            v-model="boardFilters.includeGroups"
            type="checkbox"
            class="reset-base size-4"
          />
          <span>{{ t('PIPELINES.FILTERS.INCLUDE_GROUPS') }}</span>
        </label>
      </div>

      <div
        v-if="!hasStages"
        class="flex flex-1 items-center justify-center px-6 text-center"
      >
        <div class="flex max-w-md flex-col items-center gap-3">
          <span class="i-lucide-list-plus size-8 text-n-blue-11" />
          <h2 class="m-0 text-lg font-semibold text-n-slate-12">
            {{ t('PIPELINES.EMPTY_STAGES.TITLE') }}
          </h2>
          <p class="m-0 text-sm text-n-slate-11">
            {{ t('PIPELINES.EMPTY_STAGES.DESCRIPTION') }}
          </p>
          <Button
            icon="i-lucide-plus"
            :label="t('PIPELINES.HEADER.NEW_STAGE')"
            @click="openNewStageDialog"
          />
        </div>
      </div>

      <div v-else class="flex min-h-0 flex-1 gap-3 overflow-x-auto px-5 py-4">
        <section
          v-for="stage in stages"
          :key="stage.id"
          class="flex h-full w-[21rem] flex-shrink-0 flex-col rounded-lg border border-n-weak bg-n-alpha-1"
        >
          <header
            class="flex items-start justify-between gap-2 border-b border-n-weak p-3"
          >
            <div class="flex min-w-0 flex-col gap-1">
              <div class="flex min-w-0 items-center gap-2">
                <span
                  class="size-2.5 rounded-sm"
                  :style="{ backgroundColor: stage.color }"
                />
                <h2 class="m-0 truncate text-sm font-semibold text-n-slate-12">
                  {{ stage.name }}
                </h2>
              </div>
              <div class="flex items-center gap-2 text-xs text-n-slate-10">
                <span>{{ formatCount(stage.count) }}</span>
                <span v-if="stage.stale_count">
                  {{
                    t('PIPELINES.STAGE.STALE_COUNT', {
                      count: stage.stale_count,
                    })
                  }}
                </span>
              </div>
            </div>
            <div class="flex flex-shrink-0 items-center gap-1">
              <Button
                v-tooltip.top="t('PIPELINES.STAGE.ADD_CONVERSATION')"
                icon="i-lucide-user-plus"
                slate
                xs
                @click="openCandidatesDialog(stage)"
              />
              <Button
                v-tooltip.top="t('PIPELINES.STAGE.EDIT')"
                icon="i-lucide-pencil"
                slate
                xs
                @click="openEditStageDialog(stage)"
              />
              <Button
                v-tooltip.top="t('PIPELINES.STAGE.DELETE')"
                icon="i-lucide-trash"
                slate
                xs
                class="hover:enabled:bg-n-ruby-2 hover:enabled:text-n-ruby-11"
                @click="requestDeleteStage(stage)"
              />
            </div>
          </header>

          <Draggable
            :list="stage.conversations"
            group="pipeline-conversations"
            item-key="id"
            animation="160"
            class="flex min-h-[7rem] flex-1 flex-col gap-2 overflow-y-auto p-2"
            ghost-class="opacity-50"
            @change="event => onConversationMoved(event, stage)"
          >
            <template #item="{ element }">
              <article
                class="cursor-pointer rounded-lg border border-n-weak bg-n-background p-3 shadow-sm transition-colors hover:bg-n-alpha-2"
                @click="openConversation(element)"
              >
                <div class="flex items-start justify-between gap-2">
                  <div class="min-w-0">
                    <div class="flex min-w-0 items-center gap-2">
                      <h3
                        class="m-0 truncate text-sm font-semibold text-n-slate-12"
                      >
                        {{ senderName(element) }}
                      </h3>
                      <span
                        v-if="element.is_group"
                        class="rounded bg-n-amber-9/10 px-1.5 py-0.5 text-xs text-n-amber-11"
                      >
                        {{ t('PIPELINES.CARD.GROUP') }}
                      </span>
                    </div>
                    <p
                      class="m-0 mt-1 line-clamp-2 text-xs leading-5 text-n-slate-11"
                    >
                      {{ lastMessagePreview(element) }}
                    </p>
                  </div>
                  <div class="flex flex-shrink-0 items-center gap-1">
                    <span class="text-xs text-n-slate-10">
                      {{ t('PIPELINES.CARD.ID', { id: element.id }) }}
                    </span>
                    <Button
                      v-tooltip.top="t('PIPELINES.CARD.REMOVE')"
                      icon="i-lucide-x"
                      slate
                      xs
                      :is-loading="
                        uiFlags.isRemovingConversation &&
                        removingConversationId === element.id
                      "
                      @click.stop="removeConversation(element)"
                    />
                  </div>
                </div>
                <div
                  class="mt-3 flex items-center justify-between gap-2 text-xs text-n-slate-10"
                >
                  <span class="truncate">{{ assigneeName(element) }}</span>
                  <span
                    v-if="element.priority"
                    class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-n-slate-11"
                  >
                    {{ element.priority }}
                  </span>
                </div>
              </article>
            </template>
            <template #footer>
              <div
                v-if="!stage.conversations.length"
                class="flex min-h-[7rem] items-center justify-center rounded-lg border border-dashed border-n-weak px-4 text-center text-sm text-n-slate-10"
              >
                {{ t('PIPELINES.STAGE.EMPTY') }}
              </div>
            </template>
          </Draggable>

          <div class="border-t border-n-weak p-2">
            <Button
              v-if="stage.pagination?.next_page"
              icon="i-lucide-chevron-down"
              slate
              faded
              sm
              class="w-full"
              :label="t('PIPELINES.STAGE.LOAD_MORE')"
              @click="loadMore(stage)"
            />
          </div>
        </section>
      </div>
    </section>

    <Dialog
      ref="pipelineDialogRef"
      width="md"
      :title="
        editingPipeline
          ? t('PIPELINES.PIPELINE_DIALOG.EDIT_TITLE')
          : t('PIPELINES.PIPELINE_DIALOG.CREATE_TITLE')
      "
      :confirm-button-label="t('PIPELINES.PIPELINE_DIALOG.SAVE')"
      :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
      :disable-confirm-button="!pipelineForm.name"
      @confirm="savePipeline"
    >
      <div class="grid gap-4">
        <Input
          v-model="pipelineForm.name"
          :label="t('PIPELINES.PIPELINE_DIALOG.NAME')"
          :placeholder="t('PIPELINES.PIPELINE_DIALOG.NAME_PLACEHOLDER')"
        />
        <Input
          v-model="pipelineForm.description"
          :label="t('PIPELINES.PIPELINE_DIALOG.DESCRIPTION')"
          :placeholder="t('PIPELINES.PIPELINE_DIALOG.DESCRIPTION_PLACEHOLDER')"
        />
        <Input
          v-model="pipelineForm.color"
          type="color"
          :label="t('PIPELINES.PIPELINE_DIALOG.COLOR')"
          custom-input-class="!p-1"
        />
      </div>
    </Dialog>

    <Dialog
      ref="stageDialogRef"
      width="md"
      :title="
        editingStage
          ? t('PIPELINES.STAGE_DIALOG.EDIT_TITLE')
          : t('PIPELINES.STAGE_DIALOG.CREATE_TITLE')
      "
      :confirm-button-label="t('PIPELINES.STAGE_DIALOG.SAVE')"
      :is-loading="uiFlags.isCreating || uiFlags.isUpdating"
      :disable-confirm-button="!stageForm.name"
      @confirm="saveStage"
    >
      <div class="grid gap-4">
        <Input
          v-model="stageForm.name"
          :label="t('PIPELINES.STAGE_DIALOG.NAME')"
          :placeholder="t('PIPELINES.STAGE_DIALOG.NAME_PLACEHOLDER')"
        />
        <div class="grid gap-1">
          <label class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ t('PIPELINES.STAGE_DIALOG.CATEGORY') }}
          </label>
          <select
            v-model="stageForm.category"
            class="reset-base h-10 rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
          >
            <option value="open">
              {{ t('PIPELINES.STAGE_DIALOG.CATEGORY_OPEN') }}
            </option>
            <option value="won">
              {{ t('PIPELINES.STAGE_DIALOG.CATEGORY_WON') }}
            </option>
            <option value="lost">
              {{ t('PIPELINES.STAGE_DIALOG.CATEGORY_LOST') }}
            </option>
          </select>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <Input
            v-model="stageForm.probability"
            type="number"
            min="0"
            max="100"
            :label="t('PIPELINES.STAGE_DIALOG.PROBABILITY')"
          />
          <Input
            v-model="stageForm.stale_after_days"
            type="number"
            min="1"
            :label="t('PIPELINES.STAGE_DIALOG.STALE_AFTER')"
          />
        </div>
        <Input
          v-model="stageForm.color"
          type="color"
          :label="t('PIPELINES.STAGE_DIALOG.COLOR')"
          custom-input-class="!p-1"
        />
      </div>
    </Dialog>

    <Dialog
      ref="candidateDialogRef"
      width="3xl"
      position="top"
      :title="t('PIPELINES.CANDIDATE_DIALOG.TITLE')"
      :description="t('PIPELINES.CANDIDATE_DIALOG.DESCRIPTION')"
      :cancel-button-label="t('PIPELINES.CANDIDATE_DIALOG.CLOSE')"
      :show-confirm-button="false"
      @close="closeCandidatesDialog"
    >
      <div class="grid gap-4">
        <div class="grid gap-3 md:grid-cols-[1fr_12rem_12rem_auto]">
          <Input
            v-model="candidateFilters.q"
            size="sm"
            :placeholder="t('PIPELINES.CANDIDATE_DIALOG.SEARCH_PLACEHOLDER')"
          />
          <select
            v-model="candidateFilters.stageId"
            class="reset-base h-8 rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
            :aria-label="t('PIPELINES.CANDIDATE_DIALOG.STAGE')"
          >
            <option
              v-for="stage in stageOptions"
              :key="stage.id"
              :value="stage.id"
            >
              {{ stage.name }}
            </option>
          </select>
          <select
            v-model="candidateFilters.status"
            class="reset-base h-8 rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
            :aria-label="t('PIPELINES.FILTERS.STATUS')"
          >
            <option
              v-for="option in candidateStatusOptions"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
          <label
            class="flex h-8 items-center gap-2 rounded-lg bg-n-alpha-black2 px-3 text-sm text-n-slate-11 outline outline-1 outline-n-weak"
          >
            <input
              v-model="candidateFilters.includeGroups"
              type="checkbox"
              class="reset-base size-4"
            />
            <span>{{ t('PIPELINES.FILTERS.INCLUDE_GROUPS_SHORT') }}</span>
          </label>
        </div>

        <div
          v-if="isCandidateLoading && !candidateResults.length"
          class="flex min-h-48 items-center justify-center gap-2 text-sm text-n-slate-11"
        >
          <Spinner class="size-5" />
          <span>{{ t('PIPELINES.CANDIDATE_DIALOG.LOADING') }}</span>
        </div>

        <div
          v-else-if="!candidateResults.length"
          class="flex min-h-48 items-center justify-center rounded-lg border border-dashed border-n-weak px-6 text-center text-sm text-n-slate-10"
        >
          {{ t('PIPELINES.CANDIDATE_DIALOG.EMPTY') }}
        </div>

        <div v-else class="grid max-h-[28rem] gap-2 overflow-y-auto pr-1">
          <article
            v-for="conversation in candidateResults"
            :key="conversation.uuid"
            class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-n-weak bg-n-alpha-1 p-3"
          >
            <div class="min-w-0 flex-1">
              <div class="flex min-w-0 items-center gap-2">
                <h3 class="m-0 truncate text-sm font-semibold text-n-slate-12">
                  {{ senderName(conversation) }}
                </h3>
                <span
                  v-if="conversation.is_group"
                  class="rounded bg-n-amber-9/10 px-1.5 py-0.5 text-xs text-n-amber-11"
                >
                  {{ t('PIPELINES.CARD.GROUP') }}
                </span>
                <span class="text-xs text-n-slate-10">
                  {{ t('PIPELINES.CARD.ID', { id: conversation.id }) }}
                </span>
              </div>
              <p class="m-0 mt-1 truncate text-xs text-n-slate-10">
                {{ contactDetail(conversation) }}
              </p>
              <p
                class="m-0 mt-1 line-clamp-2 text-xs leading-5 text-n-slate-11"
              >
                {{ lastMessagePreview(conversation) }}
              </p>
              <p
                v-if="conversation.pipeline"
                class="m-0 mt-1 text-xs text-n-slate-10"
              >
                {{
                  t('PIPELINES.CANDIDATE_DIALOG.CURRENT_PIPELINE', {
                    pipeline: conversation.pipeline.name,
                    stage: conversation.pipeline.stage?.name,
                  })
                }}
              </p>
            </div>
            <Button
              icon="i-lucide-plus"
              sm
              :label="t('PIPELINES.CANDIDATE_DIALOG.ADD')"
              :is-loading="addingConversationId === conversation.id"
              :disabled="!candidateFilters.stageId"
              @click="addConversationToStage(conversation)"
            />
          </article>
        </div>

        <Button
          v-if="candidateMeta.next_page"
          icon="i-lucide-chevron-down"
          slate
          faded
          sm
          class="w-full"
          :is-loading="isCandidateLoading"
          :label="t('PIPELINES.CANDIDATE_DIALOG.LOAD_MORE')"
          @click="loadMoreCandidates"
        />
      </div>
    </Dialog>

    <Dialog
      ref="deletePipelineDialogRef"
      type="alert"
      width="sm"
      :title="t('PIPELINES.DELETE_PIPELINE_DIALOG.TITLE')"
      :description="t('PIPELINES.DELETE_PIPELINE_DIALOG.DESCRIPTION')"
      :confirm-button-label="t('PIPELINES.DELETE_PIPELINE_DIALOG.CONFIRM')"
      :is-loading="uiFlags.isDeleting"
      @confirm="confirmDeletePipeline"
    />

    <Dialog
      ref="deleteStageDialogRef"
      type="alert"
      width="sm"
      :title="t('PIPELINES.DELETE_STAGE_DIALOG.TITLE')"
      :description="t('PIPELINES.DELETE_STAGE_DIALOG.DESCRIPTION')"
      :confirm-button-label="t('PIPELINES.DELETE_STAGE_DIALOG.CONFIRM')"
      :is-loading="uiFlags.isDeleting"
      @confirm="confirmDeleteStage"
    />
  </main>
</template>
