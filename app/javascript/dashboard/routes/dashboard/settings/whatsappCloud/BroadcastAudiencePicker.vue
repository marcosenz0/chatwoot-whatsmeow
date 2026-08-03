<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import { whatsappCloudAudienceImportsAPI } from 'dashboard/api/whatsappCloudStudio';
import StudioSelect from './StudioSelect.vue';
import {
  buildAudiencePreview,
  contactsFromMatrix,
  contactsFromPastedText,
  detectAudienceColumns,
  readAudienceFile,
} from './audienceImportUtils';

const props = defineProps({
  inboxId: { type: Number, required: true },
  labels: { type: Array, default: () => [] },
  labelIds: { type: Array, default: () => [] },
  contactIds: { type: Array, default: () => [] },
  consentConfirmed: { type: Boolean, default: false },
});

const emit = defineEmits(['update:labelIds', 'update:contactIds']);
const { t } = useI18n();

const sourceMode = ref('labels');
const labelSearch = ref('');
const pastedContacts = ref('');
const fileInput = ref(null);
const fileName = ref('');
const fileMatrix = ref([]);
const isDraggingFile = ref(false);
const isReadingFile = ref(false);
const isImporting = ref(false);
const importResult = ref(null);
const columns = reactive({ hasHeader: false, phone: 0, name: -1, company: -1 });

const filteredLabels = computed(() => {
  const search = labelSearch.value.trim().toLowerCase();
  if (!search) return props.labels;
  return props.labels.filter(label =>
    label.title.toLowerCase().includes(search)
  );
});

const fileColumns = computed(() => {
  const count = Math.max(0, ...fileMatrix.value.map(row => row.length));
  return Array.from({ length: count }, (_, index) => ({
    index,
    label:
      columns.hasHeader && fileMatrix.value[0]?.[index]
        ? String(fileMatrix.value[0][index])
        : t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.COLUMN', {
            count: index + 1,
          }),
  }));
});

const rawContacts = computed(() => {
  if (sourceMode.value === 'paste') {
    return contactsFromPastedText(pastedContacts.value);
  }
  if (sourceMode.value === 'file') {
    return contactsFromMatrix(fileMatrix.value, columns);
  }
  return [];
});

const preview = computed(() => buildAudiencePreview(rawContacts.value));
const previewRows = computed(() => preview.value.valid.slice(0, 8));

const sourceModeLabel = mode => {
  const labels = {
    labels: t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.MODE_LABELS'),
    paste: t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.MODE_PASTE'),
    file: t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.MODE_FILE'),
  };
  return labels[mode];
};

const invalidatePreparedAudience = () => {
  importResult.value = null;
  if (props.contactIds.length) emit('update:contactIds', []);
};

watch(
  [
    pastedContacts,
    fileMatrix,
    () => columns.phone,
    () => columns.name,
    () => columns.company,
  ],
  invalidatePreparedAudience
);

const selectSourceMode = mode => {
  sourceMode.value = mode;
  importResult.value = null;
  if (mode === 'labels') {
    emit('update:contactIds', []);
  } else {
    emit('update:labelIds', []);
  }
};

const toggleLabel = labelId => {
  const selectedIds = props.labelIds.map(Number);
  emit(
    'update:labelIds',
    selectedIds.includes(Number(labelId))
      ? selectedIds.filter(id => id !== Number(labelId))
      : [...selectedIds, Number(labelId)]
  );
};

const loadFile = async file => {
  if (!file) return;
  const validExtension = /\.(csv|xlsx)$/i.test(file.name);
  if (!validExtension) {
    useAlert(t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.FILE_TYPE_ERROR'));
    return;
  }

  isReadingFile.value = true;
  try {
    const matrix = await readAudienceFile(file);
    fileName.value = file.name;
    fileMatrix.value = matrix;
    Object.assign(columns, detectAudienceColumns(matrix));
  } catch (error) {
    useAlert(t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.FILE_READ_ERROR'));
  } finally {
    isReadingFile.value = false;
  }
};

const handleFileSelection = event => {
  loadFile(event.target.files?.[0]);
  event.target.value = '';
};

const handleDrop = event => {
  isDraggingFile.value = false;
  loadFile(event.dataTransfer?.files?.[0]);
};

const prepareAudience = async () => {
  if (!props.consentConfirmed) {
    useAlert(t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.CONSENT_REQUIRED'));
    return;
  }
  if (!preview.value.valid.length || isImporting.value) return;

  isImporting.value = true;
  try {
    const response = await whatsappCloudAudienceImportsAPI.create({
      inboxId: props.inboxId,
      contacts: preview.value.valid,
      consentConfirmed: props.consentConfirmed,
    });
    importResult.value = response.data;
    emit('update:contactIds', response.data.contact_ids || []);
    useAlert(
      t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.IMPORT_SUCCESS', {
        count: response.data.imported,
      })
    );
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.IMPORT_ERROR')
    );
  } finally {
    isImporting.value = false;
  }
};
</script>

<template>
  <fieldset class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4">
    <legend class="px-1 text-sm font-semibold text-n-slate-12">
      {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.TITLE') }}
    </legend>
    <p class="mt-1 text-xs leading-5 text-n-slate-9">
      {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.DESCRIPTION') }}
    </p>

    <div class="mt-4 grid grid-cols-3 gap-1 rounded-xl bg-n-alpha-2 p-1">
      <button
        v-for="mode in ['labels', 'paste', 'file']"
        :key="mode"
        type="button"
        class="flex min-h-10 items-center justify-center gap-2 rounded-lg px-2 text-xs font-medium transition duration-200 motion-reduce:transition-none"
        :class="
          sourceMode === mode
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12'
        "
        :aria-pressed="sourceMode === mode"
        @click="selectSourceMode(mode)"
      >
        <span
          class="size-4"
          :class="{
            'i-lucide-tags': mode === 'labels',
            'i-lucide-list-paste': mode === 'paste',
            'i-lucide-sheet': mode === 'file',
          }"
          aria-hidden="true"
        />
        {{ sourceModeLabel(mode) }}
      </button>
    </div>

    <div v-if="sourceMode === 'labels'" class="mt-4">
      <label class="relative block">
        <span class="sr-only">
          {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.SEARCH_LABELS') }}
        </span>
        <span
          class="i-lucide-search pointer-events-none absolute left-3 top-3 size-4 text-n-slate-8"
          aria-hidden="true"
        />
        <input
          v-model="labelSearch"
          name="audience-label-search"
          type="search"
          class="reset-base !mb-0 h-10 w-full rounded-xl border border-n-strong bg-n-alpha-1 pl-9 pr-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
          :placeholder="
            t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.SEARCH_LABELS')
          "
        />
      </label>
      <div class="mt-2 max-h-48 space-y-1 overflow-y-auto pr-1">
        <label
          v-for="label in filteredLabels"
          :key="label.id"
          class="flex min-h-10 cursor-pointer items-center gap-3 rounded-lg px-3 text-sm text-n-slate-11 hover:bg-n-alpha-2"
        >
          <input
            type="checkbox"
            class="reset-base size-4 rounded border-n-strong text-n-brand focus:ring-n-brand"
            :checked="labelIds.map(Number).includes(Number(label.id))"
            @change="toggleLabel(label.id)"
          />
          <span class="size-2.5 rounded-full bg-n-blue-9" aria-hidden="true" />
          <span class="truncate">{{ label.title }}</span>
        </label>
        <p
          v-if="!filteredLabels.length"
          class="py-6 text-center text-xs text-n-slate-9"
        >
          {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.NO_LABELS') }}
        </p>
      </div>
      <p class="mt-2 text-xs text-n-slate-9">
        {{
          t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.LABELS_SELECTED', {
            count: labelIds.length,
          })
        }}
      </p>
    </div>

    <div v-else-if="sourceMode === 'paste'" class="mt-4">
      <label class="flex flex-col gap-1 text-xs font-medium text-n-slate-11">
        {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.PASTE_LABEL') }}
        <textarea
          v-model="pastedContacts"
          name="pasted-whatsapp-contacts"
          rows="7"
          class="reset-base !mb-0 min-h-36 resize-y rounded-xl border border-n-strong bg-n-alpha-1 px-3 py-2 font-mono text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
          :placeholder="
            t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.PASTE_PLACEHOLDER')
          "
        />
      </label>
      <p class="mt-2 text-xs leading-5 text-n-slate-9">
        {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.PASTE_HINT') }}
      </p>
    </div>

    <div v-else class="mt-4">
      <input
        ref="fileInput"
        type="file"
        accept=".csv,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        class="sr-only"
        @change="handleFileSelection"
      />
      <button
        type="button"
        class="flex min-h-32 w-full flex-col items-center justify-center rounded-xl border border-dashed p-5 text-center transition"
        :class="
          isDraggingFile
            ? 'border-n-brand bg-n-blue-2'
            : 'border-n-strong bg-n-alpha-1 hover:border-n-brand hover:bg-n-alpha-2'
        "
        @click="fileInput?.click()"
        @dragenter.prevent="isDraggingFile = true"
        @dragover.prevent="isDraggingFile = true"
        @dragleave.prevent="isDraggingFile = false"
        @drop.prevent="handleDrop"
      >
        <span
          class="i-lucide-file-up mb-2 size-7 text-n-blue-10"
          aria-hidden="true"
        />
        <span class="text-sm font-medium text-n-slate-12">
          {{
            fileName ||
            t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.FILE_TITLE')
          }}
        </span>
        <span class="mt-1 text-xs text-n-slate-9">
          {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.FILE_HINT') }}
        </span>
      </button>

      <div v-if="fileMatrix.length" class="mt-4 grid gap-3 sm:grid-cols-3">
        <label class="flex flex-col gap-1 text-xs font-medium text-n-slate-11">
          {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.PHONE_COLUMN') }}
          <StudioSelect v-model="columns.phone">
            <option
              v-for="column in fileColumns"
              :key="column.index"
              :value="column.index"
            >
              {{ column.label }}
            </option>
          </StudioSelect>
        </label>
        <label class="flex flex-col gap-1 text-xs font-medium text-n-slate-11">
          {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.NAME_COLUMN') }}
          <StudioSelect v-model="columns.name">
            <option :value="-1">
              {{ t('WHATSAPP_CLOUD_STUDIO.NOT_AVAILABLE') }}
            </option>
            <option
              v-for="column in fileColumns"
              :key="column.index"
              :value="column.index"
            >
              {{ column.label }}
            </option>
          </StudioSelect>
        </label>
        <label class="flex flex-col gap-1 text-xs font-medium text-n-slate-11">
          {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.COMPANY_COLUMN') }}
          <StudioSelect v-model="columns.company">
            <option :value="-1">
              {{ t('WHATSAPP_CLOUD_STUDIO.NOT_AVAILABLE') }}
            </option>
            <option
              v-for="column in fileColumns"
              :key="column.index"
              :value="column.index"
            >
              {{ column.label }}
            </option>
          </StudioSelect>
        </label>
      </div>
    </div>

    <Transition
      enter-active-class="motion-safe:transition motion-safe:duration-200 motion-safe:ease-out"
      enter-from-class="translate-y-2 opacity-0"
      enter-to-class="translate-y-0 opacity-100"
      leave-active-class="motion-safe:transition motion-safe:duration-150 motion-safe:ease-in"
      leave-from-class="translate-y-0 opacity-100"
      leave-to-class="translate-y-2 opacity-0"
    >
      <div
        v-if="sourceMode !== 'labels' && preview.total"
        class="mt-4 space-y-3 motion-reduce:transform-none"
      >
        <div class="grid grid-cols-3 gap-2">
          <div class="rounded-lg bg-n-teal-3 p-3 text-center">
            <div class="text-lg font-semibold text-n-teal-11">
              {{ preview.valid.length }}
            </div>
            <div class="text-[0.7rem] text-n-teal-11">
              {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.VALID') }}
            </div>
          </div>
          <div class="rounded-lg bg-n-amber-3 p-3 text-center">
            <div class="text-lg font-semibold text-n-amber-11">
              {{ preview.duplicates }}
            </div>
            <div class="text-[0.7rem] text-n-amber-11">
              {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.DUPLICATES') }}
            </div>
          </div>
          <div class="rounded-lg bg-n-ruby-3 p-3 text-center">
            <div class="text-lg font-semibold text-n-ruby-11">
              {{ preview.invalid.length }}
            </div>
            <div class="text-[0.7rem] text-n-ruby-11">
              {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.INVALID') }}
            </div>
          </div>
        </div>

        <div
          v-if="previewRows.length"
          class="overflow-hidden rounded-xl border border-n-weak"
        >
          <div
            v-for="contact in previewRows"
            :key="contact.phone_number"
            class="flex items-center justify-between gap-3 border-b border-n-weak px-3 py-2 last:border-b-0"
          >
            <div class="min-w-0">
              <div class="truncate text-xs font-medium text-n-slate-12">
                {{
                  contact.name || contact.company_name || contact.phone_number
                }}
              </div>
              <div class="text-[0.7rem] text-n-slate-9">
                {{ contact.phone_number }}
              </div>
            </div>
            <span
              class="i-lucide-circle-check size-4 shrink-0 text-n-teal-10"
              aria-hidden="true"
            />
          </div>
        </div>

        <Transition
          enter-active-class="motion-safe:transition motion-safe:duration-200 motion-safe:ease-out"
          enter-from-class="scale-95 opacity-0"
          enter-to-class="scale-100 opacity-100"
        >
          <div
            v-if="importResult"
            class="flex items-start gap-3 rounded-xl border border-n-teal-7 bg-n-teal-2 p-3 motion-reduce:transform-none"
          >
            <span
              class="i-lucide-badge-check mt-0.5 size-5 shrink-0 text-n-teal-11"
              aria-hidden="true"
            />
            <div>
              <div class="text-sm font-medium text-n-teal-11">
                {{
                  t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.READY', {
                    count: contactIds.length,
                  })
                }}
              </div>
              <div class="mt-1 text-xs text-n-teal-11">
                {{
                  t(
                    'WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.IMPORT_SUMMARY',
                    importResult
                  )
                }}
              </div>
            </div>
          </div>
        </Transition>

        <Button
          type="button"
          class="w-full"
          :label="
            importResult
              ? t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.PREPARE_AGAIN')
              : t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.AUDIENCE.PREPARE')
          "
          icon="i-lucide-users-round"
          color="slate"
          variant="outline"
          :is-loading="isImporting || isReadingFile"
          :disabled="!preview.valid.length || isImporting || isReadingFile"
          @click="prepareAudience"
        />
      </div>
    </Transition>
  </fieldset>
</template>
