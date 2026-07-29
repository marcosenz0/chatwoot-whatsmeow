<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { whatsappCloudTemplatesAPI } from 'dashboard/api/whatsappCloudStudio';
import StudioSearchInput from './StudioSearchInput.vue';
import StudioSelect from './StudioSelect.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
  templates: { type: Array, default: () => [] },
  lastUpdatedAt: { type: [String, Date], default: null },
});

const emit = defineEmits(['update']);
const { t } = useI18n();

const isCreating = ref(false);
const isSyncing = ref(false);
const templateDialogRef = ref(null);
const search = ref('');
const statusFilter = ref('all');

const createInitialForm = () => ({
  name: '',
  language: 'pt_BR',
  category: 'UTILITY',
  header: '',
  body: '',
  footer: '',
  examples: {},
  buttons: [],
});
const form = reactive(createInitialForm());

const filteredTemplates = computed(() => {
  const term = search.value.toLowerCase().trim();
  return props.templates
    .filter(template => {
      const statusMatches =
        statusFilter.value === 'all' ||
        template.status?.toLowerCase() === statusFilter.value;
      const searchMatches =
        !term ||
        template.name?.toLowerCase().includes(term) ||
        template.category?.toLowerCase().includes(term);
      return statusMatches && searchMatches;
    })
    .sort((first, second) => first.name.localeCompare(second.name));
});

const bodyVariableIds = computed(() => {
  const matches = [...form.body.matchAll(/\{\{(\d+)\}\}/g)].map(match =>
    Number(match[1])
  );
  return [...new Set(matches)].sort((first, second) => first - second);
});

const variablesAreSequential = computed(() =>
  bodyVariableIds.value.every((id, index) => id === index + 1)
);

const validHttpUrl = value => {
  try {
    const url = new URL(value);
    return ['http:', 'https:'].includes(url.protocol) && !value.includes('{{');
  } catch {
    return false;
  }
};

const validPhoneNumber = value => /^\+?[1-9]\d{6,14}$/.test(value);

const buttonIsValid = button => {
  const text = button.text.trim();
  if (!text) return false;
  if (button.type === 'QUICK_REPLY') return text.length <= 20;
  if (button.type === 'URL') return validHttpUrl(button.url.trim());
  if (button.type === 'PHONE_NUMBER') {
    return validPhoneNumber(button.phone_number.trim());
  }
  return false;
};

const canSubmit = computed(
  () =>
    form.name.trim() &&
    form.body.trim() &&
    !form.header.includes('{{') &&
    variablesAreSequential.value &&
    bodyVariableIds.value.every(id => form.examples[id]?.trim()) &&
    form.buttons.every(buttonIsValid)
);

const bodyPlaceholder = computed(() =>
  t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.BODY_PLACEHOLDER')
    .replace('__FIRST__', '{{1}}')
    .replace('__SECOND__', '{{2}}')
);

const formattedLastSync = computed(() =>
  props.lastUpdatedAt
    ? format(new Date(props.lastUpdatedAt), 'dd/MM/yyyy HH:mm')
    : t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.NEVER_SYNCED')
);

watch(bodyVariableIds, ids => {
  form.examples = Object.fromEntries(
    ids.map(id => [id, form.examples[id] || ''])
  );
});

const statusTone = status => {
  const normalized = status?.toLowerCase();
  if (normalized === 'approved') return 'bg-n-teal-3 text-n-teal-11';
  if (normalized === 'rejected') return 'bg-n-ruby-3 text-n-ruby-11';
  if (normalized === 'paused') return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-blue-3 text-n-blue-11';
};

const statusLabel = status => {
  const labels = {
    APPROVED: t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS.APPROVED'),
    PENDING: t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS.PENDING'),
    REJECTED: t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS.REJECTED'),
    PAUSED: t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS.PAUSED'),
    DISABLED: t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS.DISABLED'),
  };
  return labels[status?.toUpperCase()] || status;
};

const categoryLabel = category => {
  const labels = {
    UTILITY: t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.UTILITY'),
    MARKETING: t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.MARKETING'),
    AUTHENTICATION: t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.AUTHENTICATION'),
  };
  return labels[category?.toUpperCase()] || category;
};

const languageLabel = language => {
  const labels = {
    pt_BR: t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.LANGUAGE_PT_BR'),
    en_US: t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.LANGUAGE_EN_US'),
    es: t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.LANGUAGE_ES'),
  };
  return labels[language] || language;
};

const bodyText = template =>
  template.components?.find(component => component.type === 'BODY')?.text || '';

const resetForm = () => {
  Object.assign(form, createInitialForm());
};

const openTemplateForm = () => {
  resetForm();
  templateDialogRef.value?.open();
};

const closeTemplateForm = () => {
  templateDialogRef.value?.close();
};

const addButton = () => {
  if (form.buttons.length >= 3) return;
  form.buttons.push({
    type: 'QUICK_REPLY',
    text: '',
    url: '',
    phone_number: '',
  });
};

const buildTemplatePayload = () => {
  const body = { type: 'BODY', text: form.body.trim() };
  if (bodyVariableIds.value.length) {
    body.example = {
      body_text: [bodyVariableIds.value.map(id => form.examples[id])],
    };
  }
  const components = [];
  if (form.header.trim()) {
    components.push({
      type: 'HEADER',
      format: 'TEXT',
      text: form.header.trim(),
    });
  }
  components.push(body);
  if (form.footer.trim()) {
    components.push({ type: 'FOOTER', text: form.footer.trim() });
  }
  if (form.buttons.length) {
    components.push({
      type: 'BUTTONS',
      buttons: form.buttons.map(button => ({
        type: button.type,
        text: button.text.trim(),
        url: button.type === 'URL' ? button.url.trim() : undefined,
        phone_number:
          button.type === 'PHONE_NUMBER'
            ? button.phone_number.trim()
            : undefined,
      })),
    });
  }
  return {
    name: form.name,
    language: form.language,
    category: form.category,
    components,
  };
};

const createTemplate = async () => {
  if (!canSubmit.value || isCreating.value) return;
  isCreating.value = true;
  try {
    const response = await whatsappCloudTemplatesAPI.createForInbox(
      props.inbox.id,
      buildTemplatePayload()
    );
    emit('update', { templates: response.data.templates });
    resetForm();
    closeTemplateForm();
    useAlert(t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.CREATED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error?.response?.data?.error ||
        t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.CREATE_ERROR')
    );
  } finally {
    isCreating.value = false;
  }
};

const syncTemplates = async () => {
  if (isSyncing.value) return;

  isSyncing.value = true;
  try {
    const response = await whatsappCloudTemplatesAPI.sync(props.inbox.id);
    emit('update', response.data);
    useAlert(t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.SYNCED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error?.response?.data?.error ||
        t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.SYNC_ERROR')
    );
  } finally {
    isSyncing.value = false;
  }
};

const deleteTemplate = async template => {
  if (
    // eslint-disable-next-line no-alert
    !window.confirm(
      t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.DELETE_CONFIRM', {
        name: template.name,
      })
    )
  ) {
    return;
  }
  try {
    const response = await whatsappCloudTemplatesAPI.deleteForInbox(
      props.inbox.id,
      template.name
    );
    emit('update', { templates: response.data.templates });
    useAlert(t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.DELETED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error?.response?.data?.error ||
        t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.DELETE_ERROR')
    );
  }
};
</script>

<template>
  <div class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_24rem]">
    <section class="min-w-0">
      <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 class="text-xl font-semibold text-n-slate-12">
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.TITLE') }}
          </h2>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.DESCRIPTION') }}
          </p>
          <p class="mt-1 text-xs text-n-slate-9">
            {{
              t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.LAST_SYNC', {
                time: formattedLastSync,
              })
            }}
          </p>
        </div>
        <div class="grid w-full gap-2 sm:flex sm:w-auto">
          <Button
            class="w-full sm:w-auto"
            :label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.SYNC')"
            icon="i-lucide-refresh-cw"
            color="slate"
            variant="outline"
            :is-loading="isSyncing"
            @click="syncTemplates"
          />
          <Button
            class="w-full sm:w-auto"
            :label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.NEW')"
            icon="i-lucide-plus"
            @click="openTemplateForm"
          />
        </div>
      </div>

      <div class="mb-4 grid gap-3 sm:grid-cols-[minmax(0,1fr)_12rem]">
        <StudioSearchInput
          v-model="search"
          :label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.SEARCH_LABEL')"
          :placeholder="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.SEARCH')"
        />
        <label class="min-w-0">
          <span class="sr-only">
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS_LABEL') }}
          </span>
          <StudioSelect
            v-model="statusFilter"
            :aria-label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS_LABEL')"
          >
            <option value="all">
              {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS.ALL') }}
            </option>
            <option value="approved">
              {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS.APPROVED') }}
            </option>
            <option value="pending">
              {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS.PENDING') }}
            </option>
            <option value="rejected">
              {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS.REJECTED') }}
            </option>
            <option value="paused">
              {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS.PAUSED') }}
            </option>
            <option value="disabled">
              {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS.DISABLED') }}
            </option>
          </StudioSelect>
        </label>
      </div>

      <div
        class="overflow-hidden rounded-2xl border border-n-weak bg-n-alpha-1"
      >
        <div
          v-if="filteredTemplates.length === 0"
          class="flex min-h-64 flex-col items-center justify-center p-8 text-center"
        >
          <span
            class="i-lucide-panels-top-left mb-3 size-8 text-n-slate-9"
            aria-hidden="true"
          />
          <h3 class="text-sm font-semibold text-n-slate-12">
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.EMPTY_TITLE') }}
          </h3>
          <p class="mt-1 max-w-md text-sm text-n-slate-10">
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.EMPTY_DESCRIPTION') }}
          </p>
        </div>
        <div v-else class="overflow-x-auto">
          <table class="w-full min-w-[48rem] text-left text-sm">
            <thead
              class="border-b border-n-weak bg-n-alpha-2 text-xs uppercase text-n-slate-9"
            >
              <tr>
                <th class="px-4 py-3 font-medium">
                  {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.TABLE.NAME') }}
                </th>
                <th class="px-4 py-3 font-medium">
                  {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.TABLE.CATEGORY') }}
                </th>
                <th class="px-4 py-3 font-medium">
                  {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.TABLE.LANGUAGE') }}
                </th>
                <th class="px-4 py-3 font-medium">
                  {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.TABLE.STATUS') }}
                </th>
                <th class="px-4 py-3 text-right font-medium">
                  {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.TABLE.ACTIONS') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="template in filteredTemplates"
                :key="template.id || `${template.name}-${template.language}`"
                class="hover:bg-n-alpha-2"
              >
                <td class="max-w-md px-4 py-4">
                  <div class="font-medium text-n-slate-12">
                    {{ template.name }}
                  </div>
                  <div class="mt-1 truncate text-xs text-n-slate-9">
                    {{ bodyText(template) }}
                  </div>
                </td>
                <td class="px-4 py-4 text-n-slate-11">
                  {{ categoryLabel(template.category) }}
                </td>
                <td class="px-4 py-4 text-n-slate-11">
                  {{ languageLabel(template.language) }}
                </td>
                <td class="px-4 py-4">
                  <span
                    class="inline-flex rounded-full px-2 py-1 text-xs font-medium"
                    :class="statusTone(template.status)"
                  >
                    {{ statusLabel(template.status) }}
                  </span>
                </td>
                <td class="px-4 py-4 text-right">
                  <Button
                    :label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.DELETE')"
                    icon="i-lucide-trash-2"
                    color="ruby"
                    variant="ghost"
                    size="sm"
                    @click="deleteTemplate(template)"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>

    <aside
      class="h-fit rounded-2xl border border-n-weak bg-n-alpha-1 p-5 xl:sticky xl:top-0"
    >
      <div class="flex items-center gap-2">
        <span
          class="i-lucide-circle-dollar-sign size-5 text-n-amber-11"
          aria-hidden="true"
        />
        <h3 class="font-semibold text-n-slate-12">
          {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.CATEGORY_GUIDE.TITLE') }}
        </h3>
      </div>
      <div class="mt-4 space-y-4 text-sm">
        <div>
          <div class="font-medium text-n-slate-12">
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.CATEGORY_GUIDE.MARKETING') }}
          </div>
          <p class="mt-1 leading-5 text-n-slate-10">
            {{
              t(
                'WHATSAPP_CLOUD_STUDIO.TEMPLATES.CATEGORY_GUIDE.MARKETING_DESCRIPTION'
              )
            }}
          </p>
        </div>
        <div>
          <div class="font-medium text-n-slate-12">
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.CATEGORY_GUIDE.UTILITY') }}
          </div>
          <p class="mt-1 leading-5 text-n-slate-10">
            {{
              t(
                'WHATSAPP_CLOUD_STUDIO.TEMPLATES.CATEGORY_GUIDE.UTILITY_DESCRIPTION'
              )
            }}
          </p>
        </div>
        <div>
          <div class="font-medium text-n-slate-12">
            {{
              t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.CATEGORY_GUIDE.AUTHENTICATION')
            }}
          </div>
          <p class="mt-1 leading-5 text-n-slate-10">
            {{
              t(
                'WHATSAPP_CLOUD_STUDIO.TEMPLATES.CATEGORY_GUIDE.AUTHENTICATION_DESCRIPTION'
              )
            }}
          </p>
        </div>
      </div>
    </aside>

    <Dialog
      ref="templateDialogRef"
      width="2xl"
      overflow-y-auto
      :show-cancel-button="false"
      :show-confirm-button="false"
      @confirm="createTemplate"
      @close="resetForm"
    >
      <div class="max-h-[78vh] overflow-y-auto pr-1">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h3 class="text-lg font-semibold text-n-slate-12">
              {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.TITLE') }}
            </h3>
            <p class="mt-1 text-sm text-n-slate-10">
              {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.DESCRIPTION') }}
            </p>
          </div>
          <button
            type="button"
            class="flex size-11 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :aria-label="t('WHATSAPP_CLOUD_STUDIO.CLOSE')"
            @click="closeTemplateForm"
          >
            <span class="i-lucide-x size-4" aria-hidden="true" />
          </button>
        </div>

        <div class="mt-6 grid gap-4 sm:grid-cols-2">
          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-11"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.NAME') }}
            <input
              v-model="form.name"
              required
              pattern="[a-z0-9_]+"
              class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
              :placeholder="
                t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.NAME_PLACEHOLDER')
              "
            />
          </label>
          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-11"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.LANGUAGE') }}
            <StudioSelect
              v-model="form.language"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.LANGUAGE')"
            >
              <option value="pt_BR">
                {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.LANGUAGE_PT_BR') }}
              </option>
              <option value="en_US">
                {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.LANGUAGE_EN_US') }}
              </option>
              <option value="es">
                {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.LANGUAGE_ES') }}
              </option>
            </StudioSelect>
          </label>
          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-11 sm:col-span-2"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.CATEGORY') }}
            <StudioSelect
              v-model="form.category"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.CATEGORY')"
            >
              <option value="UTILITY">
                {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.UTILITY') }}
              </option>
              <option value="MARKETING">
                {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.MARKETING') }}
              </option>
            </StudioSelect>
          </label>
          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-11 sm:col-span-2"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.HEADER') }}
            <input
              v-model="form.header"
              maxlength="60"
              class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
            />
            <span class="text-xs font-normal text-n-slate-9">
              {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.HEADER_HINT') }}
            </span>
          </label>
          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-11 sm:col-span-2"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.BODY') }}
            <textarea
              v-model="form.body"
              required
              rows="5"
              maxlength="1024"
              class="reset-base !mb-0 min-h-28 resize-y rounded-xl border border-n-strong bg-n-alpha-1 px-3 py-2 text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
              :placeholder="bodyPlaceholder"
            />
            <span class="text-xs font-normal text-n-slate-9">
              {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.VARIABLE_HINT') }}
            </span>
            <span
              v-if="!variablesAreSequential"
              class="text-xs font-normal text-n-ruby-11"
            >
              {{
                t(
                  'WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.VARIABLE_SEQUENCE_ERROR'
                )
              }}
            </span>
          </label>

          <label
            v-for="variableId in bodyVariableIds"
            :key="variableId"
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-11"
          >
            {{
              t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.EXAMPLE', {
                id: variableId,
              })
            }}
            <input
              v-model="form.examples[variableId]"
              required
              class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
            />
          </label>

          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-11 sm:col-span-2"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.FOOTER') }}
            <input
              v-model="form.footer"
              maxlength="60"
              class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
            />
          </label>
        </div>

        <div class="mt-6">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h4 class="text-sm font-semibold text-n-slate-12">
                {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.BUTTONS') }}
              </h4>
              <p class="mt-0.5 text-xs text-n-slate-9">
                {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.BUTTONS_HINT') }}
              </p>
            </div>
            <Button
              v-if="form.buttons.length < 3"
              class="w-full sm:w-auto"
              type="button"
              :label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.ADD_BUTTON')"
              icon="i-lucide-plus"
              color="slate"
              variant="outline"
              size="sm"
              @click="addButton"
            />
          </div>
          <div class="mt-3 space-y-3">
            <div
              v-for="(button, index) in form.buttons"
              :key="index"
              class="grid gap-3 rounded-xl border border-n-weak bg-n-alpha-2 p-3 sm:grid-cols-[10rem_1fr_auto]"
            >
              <StudioSelect
                v-model="button.type"
                :aria-label="
                  t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.BUTTON_TYPE')
                "
              >
                <option value="QUICK_REPLY">
                  {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.QUICK_REPLY') }}
                </option>
                <option value="URL">
                  {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.URL') }}
                </option>
                <option value="PHONE_NUMBER">
                  {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.PHONE') }}
                </option>
              </StudioSelect>
              <div class="grid gap-2">
                <input
                  v-model="button.text"
                  required
                  :maxlength="button.type === 'QUICK_REPLY' ? 20 : 25"
                  class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                  :placeholder="
                    t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.BUTTON_TEXT')
                  "
                />
                <input
                  v-if="button.type === 'URL'"
                  v-model="button.url"
                  required
                  type="url"
                  class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                  :placeholder="
                    t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.URL_PLACEHOLDER')
                  "
                />
                <input
                  v-if="button.type === 'PHONE_NUMBER'"
                  v-model="button.phone_number"
                  required
                  type="tel"
                  class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                  :placeholder="
                    t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.PHONE_PLACEHOLDER')
                  "
                />
                <span
                  v-if="!buttonIsValid(button)"
                  class="text-xs text-n-ruby-11"
                >
                  {{
                    t(
                      'WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.BUTTON_VALIDATION_ERROR'
                    )
                  }}
                </span>
              </div>
              <button
                type="button"
                class="flex size-11 items-center justify-center rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
                :aria-label="
                  t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.REMOVE_BUTTON')
                "
                @click="form.buttons.splice(index, 1)"
              >
                <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
              </button>
            </div>
          </div>
        </div>

        <div class="mt-6 flex justify-end gap-2 border-t border-n-weak pt-4">
          <Button
            type="button"
            :label="t('WHATSAPP_CLOUD_STUDIO.CANCEL')"
            color="slate"
            variant="ghost"
            @click="closeTemplateForm"
          />
          <Button
            type="submit"
            :label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.SUBMIT')"
            :is-loading="isCreating"
            :disabled="!canSubmit || isCreating"
          />
        </div>
      </div>
    </Dialog>
  </div>
</template>
