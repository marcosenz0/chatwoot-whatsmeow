<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
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

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const pipelines = useMapGetter('pipelines/getPipelines');
const board = useMapGetter('pipelines/getBoard');
const uiFlags = useMapGetter('pipelines/getUIFlags');

const selectedPipelineId = ref(null);
const pipelineDialogRef = ref(null);
const stageDialogRef = ref(null);
const editingPipeline = ref(null);
const editingStage = ref(null);
const stagePages = reactive({});

const pipelineForm = reactive({
  name: '',
  description: '',
  color: '#2563eb',
});

const stageForm = reactive({
  name: '',
  color: '#2563eb',
  category: 'open',
  probability: 10,
  stale_after_days: 3,
});

const selectedPipeline = computed(() =>
  pipelines.value.find(
    pipeline => pipeline.id === Number(selectedPipelineId.value)
  )
);

const stages = computed(() => board.value?.stages || []);
const hasPipelines = computed(() => pipelines.value.length > 0);
const isBoardLoading = computed(
  () => uiFlags.value.isFetching || uiFlags.value.isFetchingBoard
);

const boardParams = computed(() => ({
  per_page: BOARD_PER_PAGE,
  stage_pages: JSON.stringify(stagePages),
}));

const resetStagePages = () => {
  Object.keys(stagePages).forEach(key => {
    delete stagePages[key];
  });
};

const fetchBoard = async () => {
  if (!selectedPipelineId.value) return;
  await store.dispatch('pipelines/getBoard', {
    id: selectedPipelineId.value,
    params: boardParams.value,
  });
};

const fetchPipelines = async () => {
  const records = await store.dispatch('pipelines/get');
  if (!selectedPipelineId.value && records.length) {
    selectedPipelineId.value = records[0].id;
  }
};

const openNewPipelineDialog = () => {
  editingPipeline.value = null;
  Object.assign(pipelineForm, {
    name: '',
    description: '',
    color: '#2563eb',
  });
  pipelineDialogRef.value?.open();
};

const openEditPipelineDialog = () => {
  editingPipeline.value = selectedPipeline.value;
  Object.assign(pipelineForm, {
    name: selectedPipeline.value?.name || '',
    description: selectedPipeline.value?.description || '',
    color: selectedPipeline.value?.color || '#2563eb',
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
  useAlert(t('PIPELINES.ALERTS.PIPELINE_SAVED'));
};

const openNewStageDialog = () => {
  editingStage.value = null;
  Object.assign(stageForm, {
    name: '',
    color: '#2563eb',
    category: 'open',
    probability: 10,
    stale_after_days: 3,
  });
  stageDialogRef.value?.open();
};

const openEditStageDialog = stage => {
  editingStage.value = stage;
  Object.assign(stageForm, {
    name: stage.name,
    color: stage.color || '#2563eb',
    category: stage.category || 'open',
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

const deleteStage = async stage => {
  await store.dispatch('pipelines/deleteStage', {
    pipelineId: selectedPipelineId.value,
    stageId: stage.id,
  });
  await fetchBoard();
  useAlert(t('PIPELINES.ALERTS.STAGE_DELETED'));
};

const deletePipeline = async () => {
  await store.dispatch('pipelines/delete', selectedPipelineId.value);
  selectedPipelineId.value = null;
  resetStagePages();
  await fetchPipelines();
  await fetchBoard();
  useAlert(t('PIPELINES.ALERTS.PIPELINE_DELETED'));
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

const formatCount = count => t('PIPELINES.STAGE.COUNT', { count });

watch(selectedPipelineId, async () => {
  resetStagePages();
  await fetchBoard();
});

onMounted(async () => {
  await fetchPipelines();
  await fetchBoard();
});
</script>

<template>
  <main class="flex flex-col h-full min-h-0 bg-n-background text-n-slate-12">
    <header
      class="flex flex-wrap items-center justify-between gap-3 px-5 py-4 border-b border-n-weak"
    >
      <div class="flex flex-col min-w-0">
        <div class="flex items-center gap-2">
          <span class="i-lucide-columns-3 size-5 text-n-blue-11" />
          <h1 class="m-0 text-base font-semibold text-n-slate-12">
            {{ t('PIPELINES.HEADER.TITLE') }}
          </h1>
        </div>
        <p class="m-0 mt-1 text-sm text-n-slate-11">
          {{ t('PIPELINES.HEADER.DESCRIPTION') }}
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <select
          v-model="selectedPipelineId"
          class="reset-base h-8 min-w-[13rem] rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm outline outline-1 outline-n-weak text-n-slate-12"
        >
          <option
            v-for="pipeline in pipelines"
            :key="pipeline.id"
            :value="pipeline.id"
          >
            {{ pipeline.name }}
          </option>
        </select>
        <Button
          v-tooltip.top="t('PIPELINES.HEADER.REFRESH')"
          icon="i-lucide-refresh-cw"
          slate
          sm
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
      v-if="isBoardLoading"
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

    <section v-else class="flex flex-1 min-h-0 flex-col">
      <div
        class="flex items-center justify-between gap-3 px-5 py-3 border-b border-n-weak"
      >
        <div class="flex min-w-0 items-center gap-2">
          <span
            class="size-3 rounded-sm border border-n-weak"
            :style="{ backgroundColor: selectedPipeline?.color }"
          />
          <span class="truncate text-sm font-medium text-n-slate-12">
            {{ selectedPipeline?.name }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{
              t('PIPELINES.HEADER.TOTAL', { count: board?.total_count || 0 })
            }}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <Button
            v-tooltip.top="t('PIPELINES.HEADER.DELETE_PIPELINE')"
            icon="i-lucide-trash"
            ruby
            faded
            sm
            :disabled="pipelines.length < 2"
            @click="deletePipeline"
          />
          <Button
            icon="i-lucide-plus"
            teal
            sm
            :label="t('PIPELINES.HEADER.NEW_STAGE')"
            @click="openNewStageDialog"
          />
        </div>
      </div>

      <div class="flex flex-1 min-h-0 gap-3 overflow-x-auto px-5 py-4">
        <section
          v-for="stage in stages"
          :key="stage.id"
          class="flex h-full w-[20rem] flex-shrink-0 flex-col rounded-lg border border-n-weak bg-n-alpha-1"
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
                class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                @click="deleteStage(stage)"
              />
            </div>
          </header>

          <Draggable
            :list="stage.conversations"
            group="pipeline-conversations"
            item-key="id"
            animation="160"
            class="flex flex-1 min-h-[6rem] flex-col gap-2 overflow-y-auto p-2"
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
                    <h3
                      class="m-0 truncate text-sm font-semibold text-n-slate-12"
                    >
                      {{ senderName(element) }}
                    </h3>
                    <p
                      class="m-0 mt-1 line-clamp-2 text-xs leading-5 text-n-slate-11"
                    >
                      {{ lastMessagePreview(element) }}
                    </p>
                  </div>
                  <span class="flex-shrink-0 text-xs text-n-slate-10">
                    {{ $t('PIPELINES.CARD.ID', { id: element.id }) }}
                  </span>
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
            class="reset-base h-10 rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm outline outline-1 outline-n-weak text-n-slate-12"
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
  </main>
</template>
