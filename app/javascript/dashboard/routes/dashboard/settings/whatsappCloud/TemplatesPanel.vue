<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import { whatsappCloudTemplatesAPI } from 'dashboard/api/whatsappCloudStudio';

const props = defineProps({
  inbox: { type: Object, required: true },
  templates: { type: Array, default: () => [] },
  lastUpdatedAt: { type: [String, Date], default: null },
});

const emit = defineEmits(['update']);
const { t } = useI18n();

const isCreating = ref(false);
const isSyncing = ref(false);
const showCreateForm = ref(false);
const search = ref('');
const statusFilter = ref('all');

const initialForm = {
  name: '',
  language: 'pt_BR',
  category: 'UTILITY',
  body: '',
  footer: '',
  examples: [],
  buttons: [],
};
const form = reactive(structuredClone(initialForm));

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

const canSubmit = computed(
  () =>
    form.name.trim() &&
    form.body.trim() &&
    bodyVariableIds.value.every(id => form.examples[id - 1]?.trim())
);

const formattedLastSync = computed(() =>
  props.lastUpdatedAt
    ? format(new Date(props.lastUpdatedAt), 'dd/MM/yyyy HH:mm')
    : t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.NEVER_SYNCED')
);

watch(bodyVariableIds, ids => {
  form.examples = ids.map(id => form.examples[id - 1] || '');
});

const statusTone = status => {
  const normalized = status?.toLowerCase();
  if (normalized === 'approved') return 'bg-n-teal-3 text-n-teal-11';
  if (normalized === 'rejected') return 'bg-n-ruby-3 text-n-ruby-11';
  if (normalized === 'paused') return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-blue-3 text-n-blue-11';
};

const bodyText = template =>
  template.components?.find(component => component.type === 'BODY')?.text || '';

const resetForm = () => {
  Object.assign(form, structuredClone(initialForm));
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
      body_text: [bodyVariableIds.value.map(id => form.examples[id - 1])],
    };
  }
  const components = [body];
  if (form.footer.trim()) {
    components.push({ type: 'FOOTER', text: form.footer.trim() });
  }
  if (form.buttons.length) {
    components.push({
      type: 'BUTTONS',
      buttons: form.buttons.map(button => ({
        type: button.type,
        text: button.text,
        url: button.type === 'URL' ? button.url : undefined,
        phone_number:
          button.type === 'PHONE_NUMBER' ? button.phone_number : undefined,
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
  if (!canSubmit.value) return;
  isCreating.value = true;
  try {
    const response = await whatsappCloudTemplatesAPI.createForInbox(
      props.inbox.id,
      buildTemplatePayload()
    );
    emit('update', { templates: response.data.templates });
    resetForm();
    showCreateForm.value = false;
    useAlert(t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.CREATED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.CREATE_ERROR')
    );
  } finally {
    isCreating.value = false;
  }
};

const syncTemplates = async () => {
  isSyncing.value = true;
  try {
    const response = await whatsappCloudTemplatesAPI.sync(props.inbox.id);
    emit('update', response.data);
    useAlert(t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.SYNCED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
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
        <div class="flex gap-2">
          <Button
            :label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.SYNC')"
            icon="i-lucide-refresh-cw"
            color="slate"
            variant="outline"
            :is-loading="isSyncing"
            @click="syncTemplates"
          />
          <Button
            :label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.NEW')"
            icon="i-lucide-plus"
            @click="showCreateForm = true"
          />
        </div>
      </div>

      <div class="mb-4 flex flex-wrap gap-3">
        <label class="relative min-w-64 flex-1">
          <span
            class="i-lucide-search absolute left-3 top-3 size-4 text-n-slate-9"
            aria-hidden="true"
          />
          <span class="sr-only">
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.SEARCH_LABEL') }}
          </span>
          <input
            v-model="search"
            type="search"
            class="h-10 w-full rounded-lg border border-n-strong bg-n-alpha-1 pl-9 pr-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            :placeholder="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.SEARCH')"
          />
        </label>
        <label>
          <span class="sr-only">
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.STATUS_LABEL') }}
          </span>
          <select
            v-model="statusFilter"
            class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
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
          </select>
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
                  {{ template.category }}
                </td>
                <td class="px-4 py-4 text-n-slate-11">
                  {{ template.language }}
                </td>
                <td class="px-4 py-4">
                  <span
                    class="inline-flex rounded-full px-2 py-1 text-xs font-medium"
                    :class="statusTone(template.status)"
                  >
                    {{ template.status }}
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

    <div
      v-if="showCreateForm"
      class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black6 p-4"
      role="dialog"
      aria-modal="true"
      :aria-label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.TITLE')"
      @click.self="showCreateForm = false"
    >
      <form
        class="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
        @submit.prevent="createTemplate"
      >
        <div class="flex items-start justify-between gap-4">
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
            class="flex size-9 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :aria-label="t('WHATSAPP_CLOUD_STUDIO.CLOSE')"
            @click="showCreateForm = false"
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
              class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand"
              :placeholder="
                t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.NAME_PLACEHOLDER')
              "
            />
          </label>
          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-11"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.LANGUAGE') }}
            <select
              v-model="form.language"
              class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand"
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
            </select>
          </label>
          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-11 sm:col-span-2"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.CATEGORY') }}
            <select
              v-model="form.category"
              class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand"
            >
              <option value="UTILITY">
                {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.UTILITY') }}
              </option>
              <option value="MARKETING">
                {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.MARKETING') }}
              </option>
              <option value="AUTHENTICATION">
                {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.AUTHENTICATION') }}
              </option>
            </select>
          </label>
          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-11 sm:col-span-2"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.BODY') }}
            <textarea
              v-model="form.body"
              required
              rows="5"
              class="resize-none rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-n-slate-12 outline-none focus:border-n-brand"
              :placeholder="
                t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.BODY_PLACEHOLDER')
              "
            />
            <span class="text-xs font-normal text-n-slate-9">
              {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.VARIABLE_HINT') }}
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
              v-model="form.examples[variableId - 1]"
              required
              class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand"
            />
          </label>

          <label
            class="flex flex-col gap-1 text-sm font-medium text-n-slate-11 sm:col-span-2"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.FOOTER') }}
            <input
              v-model="form.footer"
              class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand"
            />
          </label>
        </div>

        <div class="mt-6">
          <div class="flex items-center justify-between">
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
              <select
                v-model="button.type"
                class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
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
              </select>
              <div class="grid gap-2">
                <input
                  v-model="button.text"
                  required
                  class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                  :placeholder="
                    t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.BUTTON_TEXT')
                  "
                />
                <input
                  v-if="button.type === 'URL'"
                  v-model="button.url"
                  required
                  type="url"
                  class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                  :placeholder="
                    t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.URL_PLACEHOLDER')
                  "
                />
                <input
                  v-if="button.type === 'PHONE_NUMBER'"
                  v-model="button.phone_number"
                  required
                  class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand"
                  :placeholder="
                    t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.PHONE_PLACEHOLDER')
                  "
                />
              </div>
              <button
                type="button"
                class="flex size-10 items-center justify-center rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
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
            @click="showCreateForm = false"
          />
          <Button
            type="submit"
            :label="t('WHATSAPP_CLOUD_STUDIO.TEMPLATES.FORM.SUBMIT')"
            :is-loading="isCreating"
            :disabled="!canSubmit || isCreating"
          />
        </div>
      </form>
    </div>
  </div>
</template>
