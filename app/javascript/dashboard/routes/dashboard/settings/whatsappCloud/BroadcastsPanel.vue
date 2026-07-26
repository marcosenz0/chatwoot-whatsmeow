<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import { whatsappCloudAudienceEstimateAPI } from 'dashboard/api/whatsappCloudStudio';

const props = defineProps({
  inbox: { type: Object, required: true },
  templates: { type: Array, default: () => [] },
  labels: { type: Array, default: () => [] },
  campaigns: { type: Array, default: () => [] },
});

const { t } = useI18n();
const store = useStore();

const showCreateForm = ref(false);
const isEstimating = ref(false);
const isCreating = ref(false);
const estimate = ref(null);

const initialForm = {
  title: '',
  templateName: '',
  scheduledAt: '',
  selectedLabelIds: [],
  variables: {},
  consentConfirmed: false,
};
const form = reactive(structuredClone(initialForm));

const approvedTemplates = computed(() =>
  props.templates.filter(
    template =>
      template.status?.toLowerCase() === 'approved' &&
      template.category !== 'AUTHENTICATION'
  )
);

const selectedTemplate = computed(() =>
  approvedTemplates.value.find(template => template.name === form.templateName)
);

const templateBody = computed(
  () =>
    selectedTemplate.value?.components?.find(
      component => component.type === 'BODY'
    )?.text || ''
);

const variableIds = computed(() => {
  const matches = [...templateBody.value.matchAll(/\{\{(\d+)\}\}/g)].map(
    match => Number(match[1])
  );
  return [...new Set(matches)].sort((first, second) => first - second);
});

const officialCampaigns = computed(() =>
  props.campaigns
    .filter(campaign => campaign.inbox?.id === Number(props.inbox.id))
    .sort((first, second) => second.id - first.id)
);

const currentDateTime = computed(() => {
  const now = new Date();
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 16);
});

const canSubmit = computed(
  () =>
    form.title.trim() &&
    form.templateName &&
    form.scheduledAt &&
    form.selectedLabelIds.length &&
    form.consentConfirmed &&
    variableIds.value.every(id => form.variables[id]?.trim())
);

watch(
  () => form.templateName,
  () => {
    form.variables = {};
    estimate.value = null;
  }
);

const resetForm = () => {
  Object.assign(form, structuredClone(initialForm));
  estimate.value = null;
};

const calculateEstimate = async () => {
  if (!form.selectedLabelIds.length || !selectedTemplate.value) return;
  isEstimating.value = true;
  try {
    const response = await whatsappCloudAudienceEstimateAPI.getEstimate({
      inboxId: props.inbox.id,
      labelIds: form.selectedLabelIds,
      category: selectedTemplate.value.category,
    });
    estimate.value = response.data;
  } catch (error) {
    useAlert(t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.ESTIMATE_ERROR'));
  } finally {
    isEstimating.value = false;
  }
};

const createBroadcast = async () => {
  if (!canSubmit.value) return;
  isCreating.value = true;
  try {
    await store.dispatch('campaigns/create', {
      title: form.title,
      message: templateBody.value,
      inbox_id: props.inbox.id,
      scheduled_at: new Date(form.scheduledAt).toISOString(),
      audience: form.selectedLabelIds.map(id => ({ id, type: 'Label' })),
      trigger_rules: { whatsapp_consent_confirmed: true },
      template_params: {
        name: selectedTemplate.value.name,
        namespace: selectedTemplate.value.namespace || '',
        category: selectedTemplate.value.category,
        language: selectedTemplate.value.language,
        processed_params: {
          body: Object.fromEntries(
            variableIds.value.map(id => [String(id), form.variables[id]])
          ),
        },
      },
    });
    await store.dispatch('campaigns/get');
    resetForm();
    showCreateForm.value = false;
    useAlert(t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.CREATED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.CREATE_ERROR')
    );
  } finally {
    isCreating.value = false;
  }
};

const statusTone = status => {
  if (status === 'completed') return 'bg-n-teal-3 text-n-teal-11';
  if (status === 'processing') return 'bg-n-blue-3 text-n-blue-11';
  if (status === 'failed') return 'bg-n-ruby-3 text-n-ruby-11';
  return 'bg-n-amber-3 text-n-amber-11';
};

const statusLabel = status => {
  const labels = {
    active: t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.STATUS.ACTIVE'),
    processing: t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.STATUS.PROCESSING'),
    completed: t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.STATUS.COMPLETED'),
    failed: t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.STATUS.FAILED'),
  };
  return labels[status];
};

const templateOptionLabel = template =>
  `${template.name} - ${template.category} - ${template.language}`;

const currency = value =>
  Number(value || 0).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });

const deliveryRate = campaign => {
  const summary = campaign.delivery_summary || {};
  if (!summary.total) return 0;
  return Math.round(((summary.delivered + summary.read) / summary.total) * 100);
};
</script>

<template>
  <section>
    <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="text-xl font-semibold text-n-slate-12">
          {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.TITLE') }}
        </h2>
        <p class="mt-1 max-w-3xl text-sm text-n-slate-11">
          {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.DESCRIPTION') }}
        </p>
      </div>
      <Button
        :label="t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.NEW')"
        icon="i-lucide-send"
        @click="showCreateForm = true"
      />
    </div>

    <div class="mb-5 grid gap-4 lg:grid-cols-3">
      <div class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4">
        <div
          class="flex items-center gap-2 text-sm font-medium text-n-slate-12"
        >
          <span
            class="i-lucide-users-round size-4 text-n-blue-11"
            aria-hidden="true"
          />
          {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.GUARDRAILS.AUDIENCE') }}
        </div>
        <p class="mt-2 text-xs leading-5 text-n-slate-10">
          {{
            t(
              'WHATSAPP_CLOUD_STUDIO.BROADCASTS.GUARDRAILS.AUDIENCE_DESCRIPTION'
            )
          }}
        </p>
      </div>
      <div class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4">
        <div
          class="flex items-center gap-2 text-sm font-medium text-n-slate-12"
        >
          <span class="i-lucide-ban size-4 text-n-ruby-11" aria-hidden="true" />
          {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.GUARDRAILS.OPTOUT') }}
        </div>
        <p class="mt-2 text-xs leading-5 text-n-slate-10">
          {{
            t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.GUARDRAILS.OPTOUT_DESCRIPTION')
          }}
        </p>
      </div>
      <div class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4">
        <div
          class="flex items-center gap-2 text-sm font-medium text-n-slate-12"
        >
          <span
            class="i-lucide-receipt-text size-4 text-n-amber-11"
            aria-hidden="true"
          />
          {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.GUARDRAILS.COST') }}
        </div>
        <p class="mt-2 text-xs leading-5 text-n-slate-10">
          {{
            t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.GUARDRAILS.COST_DESCRIPTION')
          }}
        </p>
      </div>
    </div>

    <div
      v-if="officialCampaigns.length === 0"
      class="flex min-h-72 flex-col items-center justify-center rounded-2xl border border-dashed border-n-strong bg-n-alpha-1 p-8 text-center"
    >
      <span
        class="i-lucide-send mb-3 size-9 text-n-slate-9"
        aria-hidden="true"
      />
      <h3 class="text-base font-semibold text-n-slate-12">
        {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.EMPTY_TITLE') }}
      </h3>
      <p class="mt-1 max-w-lg text-sm text-n-slate-10">
        {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.EMPTY_DESCRIPTION') }}
      </p>
    </div>

    <div
      v-else
      class="overflow-hidden rounded-2xl border border-n-weak bg-n-alpha-1"
    >
      <div class="overflow-x-auto">
        <table class="w-full min-w-[64rem] text-left text-sm">
          <thead
            class="border-b border-n-weak bg-n-alpha-2 text-xs uppercase text-n-slate-9"
          >
            <tr>
              <th class="px-4 py-3 font-medium">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.TABLE.CAMPAIGN') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.TABLE.STATUS') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.TABLE.RECIPIENTS') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.TABLE.DELIVERY') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.TABLE.FAILURES') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.TABLE.ESTIMATED_COST') }}
              </th>
              <th class="px-4 py-3 font-medium">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.TABLE.SCHEDULED') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="campaign in officialCampaigns"
              :key="campaign.id"
              class="hover:bg-n-alpha-2"
            >
              <td class="px-4 py-4">
                <div class="font-medium text-n-slate-12">
                  {{ campaign.title }}
                </div>
                <div class="mt-1 text-xs text-n-slate-9">
                  {{ campaign.template_params?.name }}
                </div>
              </td>
              <td class="px-4 py-4">
                <span
                  class="rounded-full px-2 py-1 text-xs font-medium"
                  :class="statusTone(campaign.campaign_status)"
                >
                  {{ statusLabel(campaign.campaign_status) }}
                </span>
              </td>
              <td class="px-4 py-4 font-medium text-n-slate-12">
                {{ campaign.delivery_summary?.total || 0 }}
              </td>
              <td class="px-4 py-4">
                <div class="flex items-center gap-2">
                  <div
                    class="h-1.5 w-20 overflow-hidden rounded-full bg-n-slate-4"
                  >
                    <div
                      class="h-full rounded-full bg-n-teal-9"
                      :class="{
                        'w-0': deliveryRate(campaign) === 0,
                        'w-1/4':
                          deliveryRate(campaign) > 0 &&
                          deliveryRate(campaign) <= 25,
                        'w-1/2':
                          deliveryRate(campaign) > 25 &&
                          deliveryRate(campaign) <= 50,
                        'w-3/4':
                          deliveryRate(campaign) > 50 &&
                          deliveryRate(campaign) < 100,
                        'w-full': deliveryRate(campaign) === 100,
                      }"
                    />
                  </div>
                  <span class="text-xs font-medium text-n-slate-11">
                    {{
                      t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.DELIVERY_RATE', {
                        rate: deliveryRate(campaign),
                      })
                    }}
                  </span>
                </div>
              </td>
              <td class="px-4 py-4 text-n-ruby-11">
                {{ campaign.delivery_summary?.failed || 0 }}
              </td>
              <td class="px-4 py-4 font-medium text-n-slate-12">
                {{ currency(campaign.delivery_summary?.estimated_cost) }}
              </td>
              <td class="px-4 py-4 text-n-slate-10">
                {{
                  campaign.scheduled_at
                    ? format(
                        new Date(campaign.scheduled_at * 1000),
                        'dd/MM/yyyy HH:mm'
                      )
                    : t('WHATSAPP_CLOUD_STUDIO.NOT_AVAILABLE')
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div
      v-if="showCreateForm"
      class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black6 p-4"
      role="dialog"
      aria-modal="true"
      :aria-label="t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.TITLE')"
      @click.self="showCreateForm = false"
    >
      <form
        class="grid max-h-[92vh] w-full max-w-5xl overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-xl lg:grid-cols-[minmax(0,1fr)_22rem]"
        @submit.prevent="createBroadcast"
      >
        <div class="overflow-y-auto p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <h3 class="text-lg font-semibold text-n-slate-12">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.TITLE') }}
              </h3>
              <p class="mt-1 text-sm text-n-slate-10">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.DESCRIPTION') }}
              </p>
            </div>
            <button
              type="button"
              class="flex size-9 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 lg:hidden"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.CLOSE')"
              @click="showCreateForm = false"
            >
              <span class="i-lucide-x size-4" aria-hidden="true" />
            </button>
          </div>

          <div class="mt-6 grid gap-4">
            <label
              class="flex flex-col gap-1 text-sm font-medium text-n-slate-11"
            >
              {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.NAME') }}
              <input
                v-model="form.title"
                required
                class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand"
              />
            </label>
            <label
              class="flex flex-col gap-1 text-sm font-medium text-n-slate-11"
            >
              {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.TEMPLATE') }}
              <select
                v-model="form.templateName"
                required
                class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand"
              >
                <option value="">
                  {{
                    t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.SELECT_TEMPLATE')
                  }}
                </option>
                <option
                  v-for="template in approvedTemplates"
                  :key="`${template.name}-${template.language}`"
                  :value="template.name"
                >
                  {{ templateOptionLabel(template) }}
                </option>
              </select>
            </label>

            <div
              v-if="selectedTemplate"
              class="rounded-xl border border-n-weak bg-n-alpha-2 p-4"
            >
              <div class="mb-2 flex items-center justify-between text-xs">
                <span class="font-medium text-n-slate-11">
                  {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.PREVIEW') }}
                </span>
                <span
                  class="rounded-full bg-n-amber-3 px-2 py-1 font-medium text-n-amber-11"
                >
                  {{ selectedTemplate.category }}
                </span>
              </div>
              <p class="whitespace-pre-wrap text-sm leading-6 text-n-slate-12">
                {{ templateBody }}
              </p>
            </div>

            <div v-if="variableIds.length" class="grid gap-3 sm:grid-cols-2">
              <label
                v-for="variableId in variableIds"
                :key="variableId"
                class="flex flex-col gap-1 text-sm font-medium text-n-slate-11"
              >
                {{
                  t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.VARIABLE', {
                    id: variableId,
                  })
                }}
                <input
                  v-model="form.variables[variableId]"
                  required
                  class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand"
                  :placeholder="
                    t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.LIQUID_HINT')
                  "
                />
              </label>
            </div>

            <label
              class="flex flex-col gap-1 text-sm font-medium text-n-slate-11"
            >
              {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.AUDIENCE') }}
              <select
                v-model="form.selectedLabelIds"
                multiple
                required
                class="min-h-32 rounded-lg border border-n-strong bg-n-alpha-1 px-3 py-2 text-n-slate-12 outline-none focus:border-n-brand"
                @change="estimate = null"
              >
                <option
                  v-for="label in labels"
                  :key="label.id"
                  :value="label.id"
                >
                  {{ label.title }}
                </option>
              </select>
              <span class="text-xs font-normal text-n-slate-9">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.AUDIENCE_HINT') }}
              </span>
            </label>

            <label
              class="flex flex-col gap-1 text-sm font-medium text-n-slate-11"
            >
              {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.SCHEDULE') }}
              <input
                v-model="form.scheduledAt"
                required
                type="datetime-local"
                :min="currentDateTime"
                class="h-10 rounded-lg border border-n-strong bg-n-alpha-1 px-3 text-n-slate-12 outline-none focus:border-n-brand"
              />
            </label>

            <label
              class="flex cursor-pointer items-start gap-3 rounded-xl border border-n-amber-7 bg-n-amber-2 p-4"
            >
              <input
                v-model="form.consentConfirmed"
                type="checkbox"
                class="reset-base mt-0.5 size-4 rounded border-n-strong text-n-brand focus:ring-n-brand"
              />
              <span>
                <span class="block text-sm font-medium text-n-slate-12">
                  {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.CONSENT_TITLE') }}
                </span>
                <span class="mt-1 block text-xs leading-5 text-n-slate-10">
                  {{
                    t(
                      'WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.CONSENT_DESCRIPTION'
                    )
                  }}
                </span>
              </span>
            </label>
          </div>
        </div>

        <aside class="flex flex-col border-l border-n-weak bg-n-alpha-2 p-6">
          <div class="flex items-center justify-between">
            <h4 class="text-sm font-semibold text-n-slate-12">
              {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.ESTIMATE.TITLE') }}
            </h4>
            <button
              type="button"
              class="hidden size-9 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-3 hover:text-n-slate-12 lg:flex"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.CLOSE')"
              @click="showCreateForm = false"
            >
              <span class="i-lucide-x size-4" aria-hidden="true" />
            </button>
          </div>
          <Button
            class="mt-4 w-full"
            :label="t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.ESTIMATE.CALCULATE')"
            icon="i-lucide-calculator"
            color="slate"
            variant="outline"
            :is-loading="isEstimating"
            :disabled="!form.selectedLabelIds.length || !selectedTemplate"
            @click="calculateEstimate"
          />
          <div v-if="estimate" class="mt-4 space-y-3">
            <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
              <div class="text-xs text-n-slate-9">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.ESTIMATE.ELIGIBLE') }}
              </div>
              <div class="mt-1 text-2xl font-semibold text-n-slate-12">
                {{ estimate.eligible }}
              </div>
            </div>
            <div class="grid grid-cols-2 gap-2">
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <div class="text-xs text-n-slate-9">
                  {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.ESTIMATE.SKIPPED') }}
                </div>
                <div class="mt-1 font-semibold text-n-ruby-11">
                  {{ estimate.skipped }}
                </div>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <div class="text-xs text-n-slate-9">
                  {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.ESTIMATE.CATEGORY') }}
                </div>
                <div
                  class="mt-1 truncate text-xs font-semibold text-n-amber-11"
                >
                  {{ estimate.category }}
                </div>
              </div>
            </div>
            <div class="rounded-xl border border-n-teal-7 bg-n-teal-2 p-4">
              <div class="text-xs text-n-teal-11">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.ESTIMATE.COST') }}
              </div>
              <div class="mt-1 text-2xl font-semibold text-n-teal-11">
                {{ currency(estimate.estimated_cost) }}
              </div>
              <p class="mt-2 text-xs leading-5 text-n-teal-11">
                {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.ESTIMATE.DISCLAIMER') }}
              </p>
            </div>
          </div>
          <div v-else class="mt-6 text-center text-xs leading-5 text-n-slate-9">
            <span
              class="i-lucide-chart-no-axes-column-increasing mx-auto mb-2 block size-7"
              aria-hidden="true"
            />
            {{ t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.ESTIMATE.EMPTY') }}
          </div>

          <div class="mt-auto flex gap-2 border-t border-n-weak pt-5">
            <Button
              class="flex-1"
              type="button"
              :label="t('WHATSAPP_CLOUD_STUDIO.CANCEL')"
              color="slate"
              variant="ghost"
              @click="showCreateForm = false"
            />
            <Button
              class="flex-1"
              type="submit"
              :label="t('WHATSAPP_CLOUD_STUDIO.BROADCASTS.FORM.SUBMIT')"
              :is-loading="isCreating"
              :disabled="!canSubmit || isCreating"
            />
          </div>
        </aside>
      </form>
    </div>
  </section>
</template>
