<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AiToggleRow from './AiToggleRow.vue';
import AudienceSelector from './AudienceSelector.vue';
import AudienceBadge from './AudienceBadge.vue';
import { defaultAudience, audiencePayload, audienceValid } from './audience';
import ResourceVideoPlayer from './ResourceVideoPlayer.vue';
import SavedResourceLibrary from './SavedResourceLibrary.vue';

const props = defineProps({
  agentId: { type: Number, required: true },
  conversationId: { type: Number, default: null },
  globalScope: { type: Boolean, default: true },
  compact: { type: Boolean, default: false },
});
const emit = defineEmits(['saved']);
const { t } = useI18n();
const items = ref([]);
const total = ref(0);
const page = ref(1);
const pageSize = ref(24);
const search = ref('');
const busy = ref(false);
const saving = ref(false);
const error = ref('');
const formError = ref('');
const editor = ref(null);
const deleteDialog = ref(null);
const deleting = ref(null);
const upload = ref(null);
const fileDrafts = ref([]);
const activeKey = ref(null);
const editingId = ref(null);
const editorMode = ref('file');
const linkDraft = ref({});
const draft = computed(() =>
  editorMode.value === 'link'
    ? linkDraft.value
    : fileDrafts.value.find(entry => entry.key === activeKey.value)
);
const itemLimit = ref(100);
const maxFileBytes = 40 * 1024 * 1024;
let nextKey = 0;
const releasePreview = entry => {
  if (entry.localUrl) URL.revokeObjectURL(entry.localUrl);
  entry.localUrl = null;
};
const clearFiles = () => {
  fileDrafts.value.forEach(releasePreview);
  fileDrafts.value = [];
  activeKey.value = null;
  if (upload.value) upload.value.value = '';
};
onBeforeUnmount(clearFiles);
const mediaUrl = entry => entry.localUrl || entry.file_url;
const mediaKind = entry =>
  entry.file ? entry.file.type.split('/')[0] : entry.kind;
const ready = entry =>
  Boolean(
    entry.title?.trim() && entry.description?.trim() && audienceValid(entry)
  );
const readyCount = computed(() => fileDrafts.value.filter(ready).length);
const removeSelection = entry => {
  releasePreview(entry);
  if (editingId.value) entry.file = null;
  else {
    const index = fileDrafts.value.indexOf(entry);
    fileDrafts.value.splice(index, 1);
    if (activeKey.value === entry.key)
      activeKey.value =
        fileDrafts.value[Math.min(index, fileDrafts.value.length - 1)]?.key ??
        null;
  }
  if (upload.value) upload.value.value = '';
  formError.value = '';
};
let generation = 0;
const icons = {
  image: 'i-lucide-image',
  video: 'i-lucide-video',
  file: 'i-lucide-file-text',
  link: 'i-lucide-link',
};
const load = async () => {
  generation += 1;
  const current = generation;
  busy.value = true;
  try {
    const { data } = await MarcosxAiAPI.getResources(props.agentId, {
      search: search.value,
      page: page.value,
    });
    if (current !== generation) return;
    items.value = data.resources;
    total.value = data.total;
    pageSize.value = data.per_page;
    itemLimit.value = data.limit;
    error.value = '';
  } catch (failure) {
    if (current === generation)
      error.value =
        failure.response?.data?.error || t('MARCOX_AI.RESOURCES.ERROR');
  } finally {
    if (current === generation) busy.value = false;
  }
};
let initialLoad = Promise.resolve();
watch(
  () => props.agentId,
  () => {
    page.value = 1;
    initialLoad = load();
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
const openEditor = item => {
  clearFiles();
  formError.value = error.value;
  editingId.value = item?.id ?? null;
  editorMode.value = item?.kind === 'link' ? 'link' : 'file';
  linkDraft.value =
    item?.kind === 'link'
      ? { ...item }
      : {
          title: '',
          description: '',
          kind: 'link',
          url: '',
          enabled: true,
          ...defaultAudience(props.globalScope, props.conversationId),
        };
  if (item && item.kind !== 'link') {
    nextKey += 1;
    const entry = { ...item, key: nextKey };
    fileDrafts.value = [entry];
    activeKey.value = entry.key;
  }
  editor.value.open();
};
const validLink = computed(() => {
  try {
    return ['https:', 'http:'].includes(new URL(linkDraft.value.url).protocol);
  } catch {
    return false;
  }
});
const valid = computed(() =>
  editorMode.value === 'link'
    ? ready(linkDraft.value) && validLink.value
    : fileDrafts.value.length > 0 &&
      fileDrafts.value.every(
        entry => ready(entry) && (entry.file || entry.file_name)
      )
);
const selectFile = event => {
  const selected = Array.from(event.target.files || []);
  event.target.value = '';
  if (!selected.length) return;
  if (selected.some(file => file.size > maxFileBytes)) {
    formError.value = t('MARCOX_AI.RESOURCES.FILE_LIMIT');
    return;
  }
  if (
    !editingId.value &&
    total.value + fileDrafts.value.length + selected.length > itemLimit.value
  ) {
    formError.value = t('MARCOX_AI.RESOURCES.BATCH_LIMIT', {
      count: itemLimit.value - total.value,
    });
    return;
  }
  if (editingId.value) {
    releasePreview(draft.value);
    const [replacement] = selected;
    draft.value.file = replacement;
    draft.value.localUrl = URL.createObjectURL(replacement);
  } else {
    const added = selected.map(file => {
      nextKey += 1;
      return {
        key: nextKey,
        title: file.name.replace(/\.[^.]+$/, '').slice(0, 120),
        description: '',
        kind: 'file',
        enabled: true,
        ...defaultAudience(props.globalScope, props.conversationId),
        file,
        localUrl: URL.createObjectURL(file),
      };
    });
    fileDrafts.value.push(...added);
    if (activeKey.value === null) activeKey.value = added[0].key;
  }
  formError.value = '';
};
const appendResource = (data, prefix, entry) => {
  ['title', 'description', 'kind', 'enabled'].forEach(key => {
    data.append(`${prefix}[${key}]`, entry[key]);
  });
  const audience = audiencePayload(entry);
  data.append(`${prefix}[audience]`, audience.audience);
  if (audience.conversation_id)
    data.append(`${prefix}[conversation_id]`, audience.conversation_id);
  audience.contact_ids.forEach(id =>
    data.append(`${prefix}[contact_ids][]`, id)
  );
  if (entry.kind === 'link') data.append(`${prefix}[url]`, entry.url.trim());
  else if (entry.file) data.append(`${prefix}[file]`, entry.file);
};
const save = async () => {
  if (!valid.value || saving.value) return;
  const id = props.agentId;
  saving.value = true;
  formError.value = '';
  const data = new FormData();
  try {
    if (editingId.value || editorMode.value === 'link') {
      appendResource(data, 'resource', draft.value);
      await MarcosxAiAPI.saveResource(id, editingId.value ?? undefined, data);
    } else {
      fileDrafts.value.forEach(entry =>
        appendResource(data, 'resources[]', entry)
      );
      await MarcosxAiAPI.saveResourceBatch(id, data);
    }
    editor.value.close();
    await load();
    emit('saved');
  } catch (failure) {
    formError.value =
      failure.response?.data?.error || t('MARCOX_AI.RESOURCES.ERROR');
  } finally {
    saving.value = false;
  }
};
const toggle = async item => {
  if (saving.value) return;
  saving.value = true;
  try {
    await MarcosxAiAPI.saveResource(props.agentId, item.id, {
      resource: { enabled: !item.enabled },
    });
    await load();
  } catch (failure) {
    error.value =
      failure.response?.data?.error || t('MARCOX_AI.RESOURCES.ERROR');
  } finally {
    saving.value = false;
  }
};
const libraryUpdated = () => {
  load();
  emit('saved');
};
const requestDelete = item => {
  deleting.value = item;
  deleteDialog.value.open();
};
const remove = async () => {
  saving.value = true;
  try {
    await MarcosxAiAPI.deleteResource(props.agentId, deleting.value.id);
    deleteDialog.value.close();
    if (items.value.length === 1 && page.value > 1) page.value -= 1;
    else await load();
  } catch (failure) {
    error.value =
      failure.response?.data?.error || t('MARCOX_AI.RESOURCES.ERROR');
  } finally {
    saving.value = false;
  }
};
defineExpose({
  openCreate: async () => {
    await initialLoad;
    if (editor.value) openEditor();
  },
});
</script>

<template>
  <section
    :class="compact ? '' : 'min-h-0 min-w-0 flex-1 overflow-y-auto p-4 sm:p-6'"
  >
    <div v-if="!compact" class="mx-auto w-full max-w-6xl space-y-5">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="max-w-2xl">
          <h3 class="m-0 text-lg font-semibold text-n-slate-12">
            {{ t('MARCOX_AI.RESOURCES.TITLE') }}
          </h3>
          <p class="mb-0 mt-2 text-sm leading-6 text-n-slate-11">
            {{ t('MARCOX_AI.RESOURCES.HINT') }}
          </p>
        </div>
        <Button
          :label="t('MARCOX_AI.RESOURCES.ADD')"
          icon="i-lucide-plus"
          @click="openEditor()"
        />
      </div>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <input
          v-model="search"
          type="search"
          class="reset-base h-10 w-full max-w-sm rounded-lg border border-n-weak bg-n-background px-3 text-sm"
          :placeholder="t('MARCOX_AI.RESOURCES.SEARCH')"
          :aria-label="t('MARCOX_AI.RESOURCES.SEARCH')"
        />
        <span class="text-xs text-n-slate-11">
          {{ t('MARCOX_AI.RESOURCES.COUNT', { count: total }) }}
        </span>
      </div>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <p v-if="busy" class="text-sm text-n-slate-11">
        {{ t('MARCOX_AI.RESOURCES.LOADING') }}
      </p>
      <div
        v-else-if="!items.length"
        class="flex flex-col items-center gap-3 rounded-xl border border-dashed border-n-weak bg-n-solid-2 px-5 py-12 text-center"
      >
        <span class="i-lucide-folder-open size-9 text-n-blue-9" />
        <p class="m-0 text-sm font-medium text-n-slate-12">
          {{ t('MARCOX_AI.RESOURCES.EMPTY') }}
        </p>
        <p class="m-0 max-w-lg text-sm text-n-slate-11">
          {{ t('MARCOX_AI.RESOURCES.EMPTY_HINT') }}
        </p>
      </div>
      <div v-else class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <article
          v-for="item in items"
          :key="item.id"
          class="min-w-0 overflow-hidden rounded-xl border border-n-weak bg-n-solid-2"
        >
          <div class="flex h-32 items-center justify-center bg-n-alpha-1">
            <img
              v-if="item.thumb_url"
              :src="item.thumb_url"
              :alt="item.title"
              loading="lazy"
              class="h-full w-full object-contain"
            />
            <video
              v-else-if="item.kind === 'video'"
              :src="`${item.file_url}#t=0.001`"
              :aria-label="item.title"
              preload="metadata"
              muted
              playsinline
              class="h-full w-full object-contain"
            />
            <span
              v-else
              :class="icons[item.kind]"
              class="size-9 text-n-slate-10"
            />
          </div>
          <div class="space-y-3 p-4">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h4 class="m-0 truncate text-sm font-semibold text-n-slate-12">
                  {{ item.title }}
                </h4>
                <p class="mb-0 mt-1 text-xs text-n-slate-11">
                  {{ t(`MARCOX_AI.RESOURCES.KIND_${item.kind.toUpperCase()}`) }}
                </p>
              </div>
              <span
                class="shrink-0 rounded-md px-2 py-1 text-xs"
                :class="
                  item.enabled
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-alpha-2 text-n-slate-11'
                "
              >
                {{
                  t(
                    item.enabled
                      ? 'MARCOX_AI.RESOURCES.AVAILABLE'
                      : 'MARCOX_AI.RESOURCES.DISABLED'
                  )
                }}
              </span>
            </div>
            <AudienceBadge :item="item" />
            <p
              class="m-0 line-clamp-3 min-h-[4.5rem] break-words text-sm leading-6 text-n-slate-11"
            >
              {{ item.description }}
            </p>
            <div
              class="flex items-center justify-between gap-2 border-t border-n-weak pt-3"
            >
              <a
                :href="item.kind === 'link' ? item.url : item.file_url"
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center gap-1.5 text-xs font-medium text-n-blue-11"
              >
                <span class="i-lucide-external-link size-3.5" />
                {{ t('MARCOX_AI.RESOURCES.OPEN') }}
              </a>
              <div class="flex gap-1">
                <Button
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-power"
                  :disabled="saving"
                  :aria-label="
                    t(
                      item.enabled
                        ? 'MARCOX_AI.RESOURCES.DISABLE'
                        : 'MARCOX_AI.RESOURCES.ENABLE'
                    )
                  "
                  @click="toggle(item)"
                />
                <Button
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-pencil"
                  :aria-label="t('MARCOX_AI.RESOURCES.EDIT')"
                  @click="openEditor(item)"
                />
                <Button
                  variant="ghost"
                  color="ruby"
                  icon="i-lucide-trash-2"
                  :aria-label="t('MARCOX_AI.RESOURCES.DELETE')"
                  @click="requestDelete(item)"
                />
              </div>
            </div>
          </div>
        </article>
      </div>
      <div
        v-if="total > pageSize"
        class="flex items-center justify-end gap-3 text-sm text-n-slate-11"
      >
        <Button
          variant="ghost"
          icon="i-lucide-chevron-left"
          :aria-label="t('MARCOX_AI.WORKSPACE.PREVIOUS')"
          :disabled="busy || page === 1"
          @click="page -= 1"
        />
        <span>{{ page }} / {{ Math.ceil(total / pageSize) }}</span>
        <Button
          variant="ghost"
          icon="i-lucide-chevron-right"
          :aria-label="t('MARCOX_AI.WORKSPACE.NEXT')"
          :disabled="busy || page >= Math.ceil(total / pageSize)"
          @click="page += 1"
        />
      </div>
      <p class="text-xs leading-5 text-n-slate-11">
        {{ t('MARCOX_AI.RESOURCES.SAVE_HINT') }}
      </p>
    </div>
    <Dialog
      ref="editor"
      width="3xl"
      :title="
        t(editingId ? 'MARCOX_AI.RESOURCES.EDIT' : 'MARCOX_AI.RESOURCES.ADD')
      "
      :confirm-button-label="
        !editingId && editorMode === 'file' && fileDrafts.length > 1
          ? t('MARCOX_AI.RESOURCES.SAVE_ITEMS', { count: fileDrafts.length })
          : t('MARCOX_AI.RESOURCES.SAVE')
      "
      :cancel-button-label="t('MARCOX_AI.CANCEL')"
      :disable-confirm-button="!valid || saving"
      :is-loading="saving"
      :prevent-close="saving"
      @confirm="save"
      @close="clearFiles"
    >
      <div class="max-h-[60vh] space-y-5 overflow-y-auto p-1">
        <SavedResourceLibrary
          v-if="!editingId"
          :agent-id="agentId"
          :conversation-id="conversationId"
          :disabled="saving"
          @updated="libraryUpdated"
        />
        <div v-if="!editingId" class="grid grid-cols-2 gap-2">
          <Button
            type="button"
            :variant="editorMode === 'file' ? 'solid' : 'outline'"
            icon="i-lucide-paperclip"
            :label="t('MARCOX_AI.RESOURCES.UPLOAD')"
            :disabled="saving"
            @click="editorMode = 'file'"
          />
          <Button
            type="button"
            :variant="editorMode === 'link' ? 'solid' : 'outline'"
            icon="i-lucide-link"
            :label="t('MARCOX_AI.RESOURCES.KIND_LINK')"
            :disabled="saving"
            @click="editorMode = 'link'"
          />
        </div>
        <template v-if="editorMode === 'file'">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="space-y-1">
              <p class="m-0 text-sm font-medium text-n-slate-12">
                {{
                  t('MARCOX_AI.RESOURCES.SELECTION_COUNT', {
                    count: fileDrafts.length,
                  })
                }}
              </p>
              <p class="m-0 text-xs leading-5 text-n-slate-11">
                {{
                  t(
                    editingId
                      ? 'MARCOX_AI.RESOURCES.DESCRIPTION_HELP'
                      : 'MARCOX_AI.RESOURCES.BATCH_HINT'
                  )
                }}
              </p>
            </div>
            <input
              ref="upload"
              type="file"
              :multiple="!editingId"
              accept="image/jpeg,image/png,image/webp,image/gif,video/mp4,video/webm,video/quicktime,application/pdf,text/plain"
              class="hidden"
              :disabled="saving"
              :aria-label="t('MARCOX_AI.RESOURCES.UPLOAD')"
              @change="selectFile"
            />
            <Button
              type="button"
              variant="outline"
              color="slate"
              icon="i-lucide-upload"
              :disabled="saving"
              :label="
                t(
                  editingId
                    ? 'MARCOX_AI.RESOURCES.REPLACE_FILE'
                    : fileDrafts.length
                      ? 'MARCOX_AI.RESOURCES.ADD_FILES'
                      : 'MARCOX_AI.RESOURCES.SELECT_FILES'
                )
              "
              @click="upload.click()"
            />
          </div>
          <div
            v-if="fileDrafts.length"
            role="group"
            :aria-label="t('MARCOX_AI.RESOURCES.SELECTED_FILES')"
            class="grid grid-cols-2 gap-3 sm:grid-cols-4"
          >
            <div
              v-for="entry in fileDrafts"
              :key="entry.key"
              class="relative min-w-0"
              data-testid="resource-draft"
            >
              <button
                type="button"
                :aria-label="
                  t('MARCOX_AI.RESOURCES.EDIT_SELECTION', {
                    name: entry.file?.name || entry.file_name,
                  })
                "
                :aria-pressed="entry.key === activeKey"
                :disabled="saving"
                class="reset-base relative block aspect-square w-full overflow-hidden rounded-xl !border-2 !border-solid bg-n-solid-2 text-start transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-blue-9"
                :class="
                  entry.key === activeKey
                    ? 'border-n-blue-9 ring-2 ring-n-blue-9/20'
                    : 'border-n-weak hover:border-n-slate-7'
                "
                @click="activeKey = entry.key"
              >
                <img
                  v-if="mediaKind(entry) === 'image'"
                  :src="mediaUrl(entry)"
                  :alt="entry.file?.name || entry.file_name"
                  loading="lazy"
                  class="absolute inset-0 h-full w-full object-cover"
                />
                <video
                  v-else-if="mediaKind(entry) === 'video'"
                  :src="`${mediaUrl(entry)}#t=0.001`"
                  :aria-label="entry.file?.name || entry.file_name"
                  preload="metadata"
                  muted
                  playsinline
                  class="pointer-events-none absolute inset-0 h-full w-full object-cover"
                />
                <span
                  v-else
                  class="i-lucide-file-text absolute left-1/2 top-1/2 size-9 -translate-x-1/2 -translate-y-1/2 text-n-slate-10"
                />
                <div
                  v-if="mediaKind(entry) === 'video'"
                  class="pointer-events-none absolute inset-0 flex items-center justify-center"
                >
                  <div class="rounded-full bg-n-solid-2/80 p-2">
                    <span class="i-lucide-play block size-5 text-n-slate-12" />
                  </div>
                </div>
                <span
                  class="absolute bottom-0 start-0 flex w-full items-center gap-1.5 bg-n-solid-2/90 p-2 text-xs text-n-slate-12"
                >
                  <span
                    :class="
                      ready(entry)
                        ? 'i-lucide-circle-check text-n-teal-11'
                        : 'i-lucide-pencil text-n-slate-11'
                    "
                    class="size-3.5 shrink-0"
                  />
                  <span class="truncate">{{
                    entry.file?.name || entry.file_name
                  }}</span>
                </span>
              </button>
              <Button
                v-if="!editingId || entry.file"
                type="button"
                size="xs"
                color="slate"
                icon="i-lucide-x"
                class="absolute end-2 top-2"
                :aria-label="
                  t('MARCOX_AI.RESOURCES.REMOVE_FILE', {
                    name: entry.file?.name || entry.file_name,
                  })
                "
                :disabled="saving"
                @click="removeSelection(entry)"
              />
              <AudienceBadge
                :item="entry"
                icon-only
                class="pointer-events-none absolute start-2 top-2"
              />
            </div>
          </div>
          <p
            v-else
            class="m-0 rounded-xl border border-dashed border-n-weak bg-n-solid-2 p-6 text-center text-sm text-n-slate-11"
          >
            {{ t('MARCOX_AI.RESOURCES.SELECT_FILES_HINT') }}
          </p>
          <p
            v-if="fileDrafts.length && !editingId"
            class="m-0 text-xs text-n-slate-11"
            role="status"
          >
            {{
              t('MARCOX_AI.RESOURCES.READY_COUNT', {
                ready: readyCount,
                total: fileDrafts.length,
              })
            }}
          </p>
        </template>
        <div
          v-if="draft"
          class="space-y-4 rounded-xl border border-n-weak bg-n-solid-2 p-4"
        >
          <p
            v-if="editorMode === 'file'"
            class="m-0 truncate text-sm font-semibold text-n-slate-12"
          >
            {{ draft.file?.name || draft.file_name }}
          </p>
          <ResourceVideoPlayer
            v-if="editorMode === 'file' && mediaKind(draft) === 'video'"
            :key="mediaUrl(draft)"
            :src="mediaUrl(draft)"
            :name="draft.file?.name || draft.file_name"
          />
          <div
            class="grid gap-4"
            :class="editorMode === 'link' ? 'sm:grid-cols-2' : ''"
          >
            <label class="block text-sm font-medium text-n-slate-12">
              {{ t('MARCOX_AI.RESOURCES.NAME') }}
              <input
                v-model="draft.title"
                maxlength="120"
                :disabled="saving"
                class="reset-base mt-2 block w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
                :placeholder="t('MARCOX_AI.RESOURCES.NAME_HINT')"
              />
            </label>
            <label
              v-if="editorMode === 'link'"
              class="block text-sm font-medium text-n-slate-12"
            >
              {{ t('MARCOX_AI.RESOURCES.URL') }}
              <input
                v-model="draft.url"
                type="url"
                maxlength="2048"
                :disabled="saving"
                class="reset-base mt-2 block w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
              />
            </label>
          </div>
          <label class="block text-sm font-medium text-n-slate-12">
            {{ t('MARCOX_AI.RESOURCES.DESCRIPTION') }}
            <textarea
              v-model="draft.description"
              rows="4"
              maxlength="800"
              :disabled="saving"
              class="reset-base mt-2 block min-h-28 w-full resize-y rounded-lg border border-n-weak bg-n-background p-3 text-sm"
              :placeholder="t('MARCOX_AI.RESOURCES.DESCRIPTION_HINT')"
            />
          </label>
          <p class="m-0 text-xs leading-5 text-n-slate-11">
            {{ t('MARCOX_AI.RESOURCES.DESCRIPTION_HELP') }}
          </p>
          <AudienceSelector
            :model-value="draft"
            :agent-id="agentId"
            :conversation-id="conversationId"
            @update:model-value="Object.assign(draft, $event)"
          />
          <AiToggleRow
            v-model="draft.enabled"
            :disabled="saving"
            :label="t('MARCOX_AI.RESOURCES.AVAILABLE')"
            :description="t('MARCOX_AI.RESOURCES.ENABLED_HINT')"
          />
        </div>
        <p class="text-xs text-n-slate-11">
          {{ t('MARCOX_AI.RESOURCES.FILE_LIMIT') }}
        </p>
        <p v-if="formError" role="alert" class="text-sm text-n-ruby-11">
          {{ formError }}
        </p>
      </div>
    </Dialog>
    <Dialog
      ref="deleteDialog"
      type="alert"
      :title="t('MARCOX_AI.RESOURCES.DELETE')"
      :description="
        t('MARCOX_AI.RESOURCES.DELETE_HINT', { name: deleting?.title || '' })
      "
      :confirm-button-label="t('MARCOX_AI.RESOURCES.DELETE')"
      :cancel-button-label="t('MARCOX_AI.CANCEL')"
      :is-loading="saving"
      :prevent-close="saving"
      @confirm="remove"
    />
  </section>
</template>
