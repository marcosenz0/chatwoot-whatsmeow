<script setup>
import { computed, ref, watch } from 'vue';
import { useDebounceFn, useObjectUrl } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import MarcosxAiAPI from 'dashboard/api/marcosxAi';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AiToggleRow from './AiToggleRow.vue';

const props = defineProps({ agentId: { type: Number, required: true } });
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
const file = ref(null);
const selectedFileUrl = useObjectUrl(file);
const draft = ref({});
const previewUrl = computed(
  () => selectedFileUrl.value || draft.value.file_url
);
const previewKind = computed(() =>
  file.value ? file.value.type.split('/')[0] : draft.value.kind
);
const clearFile = () => {
  file.value = null;
  if (upload.value) upload.value.value = '';
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
    error.value = '';
  } catch (failure) {
    if (current === generation)
      error.value =
        failure.response?.data?.error || t('MARCOX_AI.RESOURCES.ERROR');
  } finally {
    if (current === generation) busy.value = false;
  }
};
watch(
  () => props.agentId,
  () => {
    page.value = 1;
    load();
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
  clearFile();
  formError.value = '';
  draft.value = item
    ? { ...item }
    : { title: '', description: '', kind: 'file', url: '', enabled: true };
  editor.value.open();
};
const validLink = computed(() => {
  try {
    return ['https:', 'http:'].includes(new URL(draft.value.url).protocol);
  } catch {
    return false;
  }
});
const valid = computed(
  () =>
    draft.value.title?.trim() &&
    draft.value.description?.trim() &&
    (draft.value.kind === 'link'
      ? validLink.value
      : file.value || draft.value.file_name)
);
const selectFile = event => {
  const selected = event.target.files?.[0];
  if (!selected) return;
  if (selected.size > 40 * 1024 * 1024) {
    formError.value = t('MARCOX_AI.RESOURCES.FILE_LIMIT');
    event.target.value = '';
    return;
  }
  file.value = selected;
  formError.value = '';
};
const save = async () => {
  if (!valid.value || saving.value) return;
  const id = props.agentId;
  saving.value = true;
  formError.value = '';
  const data = new FormData();
  ['title', 'description', 'kind', 'enabled'].forEach(key => {
    data.append(`resource[${key}]`, draft.value[key]);
  });
  if (draft.value.kind === 'link')
    data.append('resource[url]', draft.value.url.trim());
  if (draft.value.kind !== 'link' && file.value)
    data.append('resource[file]', file.value);
  try {
    await MarcosxAiAPI.saveResource(id, draft.value.id, data);
    editor.value.close();
    await load();
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
</script>

<template>
  <section class="min-h-0 min-w-0 flex-1 overflow-y-auto p-4 sm:p-6">
    <div class="mx-auto w-full max-w-6xl space-y-5">
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
      width="2xl"
      :title="
        t(draft.id ? 'MARCOX_AI.RESOURCES.EDIT' : 'MARCOX_AI.RESOURCES.ADD')
      "
      :confirm-button-label="t('MARCOX_AI.RESOURCES.SAVE')"
      :cancel-button-label="t('MARCOX_AI.CANCEL')"
      :disable-confirm-button="!valid || saving"
      :is-loading="saving"
      :prevent-close="saving"
      @confirm="save"
      @close="clearFile"
    >
      <div class="max-h-[58vh] space-y-5 overflow-y-auto p-1">
        <div v-if="!draft.id" class="grid grid-cols-2 gap-2">
          <Button
            type="button"
            :variant="draft.kind === 'file' ? 'solid' : 'outline'"
            icon="i-lucide-paperclip"
            :label="t('MARCOX_AI.RESOURCES.UPLOAD')"
            @click="draft.kind = 'file'"
          />
          <Button
            type="button"
            :variant="draft.kind === 'link' ? 'solid' : 'outline'"
            icon="i-lucide-link"
            :label="t('MARCOX_AI.RESOURCES.KIND_LINK')"
            @click="draft.kind = 'link'"
          />
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <label class="block text-sm font-medium text-n-slate-12">
            {{ t('MARCOX_AI.RESOURCES.NAME') }}
            <input
              v-model="draft.title"
              maxlength="120"
              class="reset-base mt-2 block w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
              :placeholder="t('MARCOX_AI.RESOURCES.NAME_HINT')"
            />
          </label>
          <label
            v-if="draft.kind === 'link'"
            class="block text-sm font-medium text-n-slate-12"
          >
            {{ t('MARCOX_AI.RESOURCES.URL') }}
            <input
              v-model="draft.url"
              type="url"
              maxlength="2048"
              class="reset-base mt-2 block w-full rounded-lg border border-n-weak bg-n-background p-3 text-sm"
            />
          </label>
          <div v-else class="space-y-2 text-sm">
            <p class="m-0 font-medium text-n-slate-12">
              {{ t('MARCOX_AI.RESOURCES.UPLOAD') }}
            </p>
            <input
              ref="upload"
              type="file"
              accept="image/jpeg,image/png,image/webp,image/gif,video/mp4,video/webm,video/quicktime,application/pdf,text/plain"
              class="hidden"
              :aria-label="t('MARCOX_AI.RESOURCES.UPLOAD')"
              @change="selectFile"
            />
            <Button
              type="button"
              variant="outline"
              color="slate"
              icon="i-lucide-upload"
              :label="
                t(
                  draft.file_name
                    ? 'MARCOX_AI.RESOURCES.REPLACE_FILE'
                    : 'MARCOX_AI.RESOURCES.SELECT_FILE'
                )
              "
              @click="upload.click()"
            />
            <p v-if="!previewUrl" class="m-0 break-all text-xs text-n-slate-11">
              {{ file?.name || draft.file_name }}
            </p>
          </div>
        </div>
        <div
          v-if="draft.kind !== 'link' && previewUrl"
          class="relative overflow-hidden rounded-xl border border-n-weak bg-n-alpha-1"
        >
          <div class="flex h-40 items-center justify-center p-3">
            <img
              v-if="previewKind === 'image'"
              :src="previewUrl"
              :alt="file?.name || draft.file_name"
              class="h-full w-full object-contain"
            />
            <video
              v-else-if="previewKind === 'video'"
              :src="`${previewUrl}#t=0.001`"
              :aria-label="file?.name || draft.file_name"
              preload="metadata"
              controls
              playsinline
              class="h-full w-full object-contain"
            />
            <span v-else class="i-lucide-file-text size-10 text-n-slate-10" />
          </div>
          <Button
            v-if="file"
            type="button"
            size="xs"
            color="slate"
            icon="i-lucide-x"
            class="absolute right-2 top-2"
            :aria-label="t('MARCOX_AI.RESOURCES.REMOVE_SELECTION')"
            :disabled="saving"
            @click="clearFile"
          />
          <p
            class="m-0 break-all border-t border-n-weak p-3 text-xs text-n-slate-11"
          >
            {{ file?.name || draft.file_name }}
          </p>
        </div>
        <label class="block text-sm font-medium text-n-slate-12">
          {{ t('MARCOX_AI.RESOURCES.DESCRIPTION') }}
          <textarea
            v-model="draft.description"
            rows="4"
            maxlength="800"
            class="reset-base mt-2 block min-h-28 w-full resize-y rounded-lg border border-n-weak bg-n-background p-3 text-sm"
            :placeholder="t('MARCOX_AI.RESOURCES.DESCRIPTION_HINT')"
          />
          <span
            class="mt-2 block text-xs font-normal leading-5 text-n-slate-11"
            >{{ t('MARCOX_AI.RESOURCES.DESCRIPTION_HELP') }}</span
          >
        </label>
        <AiToggleRow
          v-model="draft.enabled"
          :label="t('MARCOX_AI.RESOURCES.AVAILABLE')"
          :description="t('MARCOX_AI.RESOURCES.ENABLED_HINT')"
        />
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
