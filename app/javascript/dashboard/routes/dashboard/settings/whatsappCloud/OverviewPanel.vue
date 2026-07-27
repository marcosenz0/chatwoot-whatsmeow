<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';

const props = defineProps({
  inbox: { type: Object, default: null },
  templates: { type: Array, default: () => [] },
  automations: { type: Array, default: () => [] },
  campaigns: { type: Array, default: () => [] },
  templatesLastUpdatedAt: { type: [String, Date], default: null },
});

const emit = defineEmits(['openTab']);
const { t } = useI18n();

const approvedTemplates = computed(
  () =>
    props.templates.filter(
      template => template.status?.toLowerCase() === 'approved'
    ).length
);
const pendingTemplates = computed(
  () =>
    props.templates.filter(
      template => template.status?.toLowerCase() === 'pending'
    ).length
);
const activeFlows = computed(
  () => props.automations.filter(flow => flow.status === 'active').length
);
const runningContacts = computed(() =>
  props.automations.reduce(
    (total, flow) => total + (flow.run_summary?.running || 0),
    0
  )
);
const officialCampaigns = computed(() =>
  props.campaigns.filter(
    campaign => campaign.inbox?.id === Number(props.inbox?.id)
  )
);
const estimatedSpend = computed(() =>
  officialCampaigns.value.reduce(
    (total, campaign) =>
      total + Number(campaign.delivery_summary?.estimated_cost || 0),
    0
  )
);

const cards = computed(() => [
  {
    label: t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.CARDS.APPROVED_TEMPLATES'),
    value: approvedTemplates.value,
    secondary: t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.CARDS.PENDING_TEMPLATES', {
      count: pendingTemplates.value,
    }),
    icon: 'i-lucide-badge-check',
    tone: 'text-n-teal-11 bg-n-teal-3',
    tab: 'templates',
  },
  {
    label: t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.CARDS.ACTIVE_FLOWS'),
    value: activeFlows.value,
    secondary: t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.CARDS.RUNNING_CONTACTS', {
      count: runningContacts.value,
    }),
    icon: 'i-lucide-workflow',
    tone: 'text-n-blue-11 bg-n-blue-3',
    tab: 'flows',
  },
  {
    label: t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.CARDS.BROADCASTS'),
    value: officialCampaigns.value.length,
    secondary: t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.CARDS.ESTIMATED_SPEND', {
      amount: estimatedSpend.value.toLocaleString('pt-BR', {
        style: 'currency',
        currency: 'BRL',
      }),
    }),
    icon: 'i-lucide-send',
    tone: 'text-n-amber-11 bg-n-amber-3',
    tab: 'broadcasts',
  },
]);

const formattedLastSync = computed(() => {
  if (!props.templatesLastUpdatedAt) {
    return t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.NEVER_SYNCED');
  }
  return format(new Date(props.templatesLastUpdatedAt), 'dd/MM/yyyy HH:mm');
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <section
      class="grid gap-4 rounded-2xl border border-n-weak bg-gradient-to-br from-n-teal-2 to-n-blue-2 p-6 lg:grid-cols-[1fr_auto]"
    >
      <div>
        <div class="mb-3 flex items-center gap-2">
          <span
            class="i-lucide-shield-check size-5 text-n-teal-11"
            aria-hidden="true"
          />
          <span class="text-sm font-semibold text-n-teal-11">
            {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.COMPLIANCE_LABEL') }}
          </span>
        </div>
        <h2 class="text-xl font-semibold text-n-slate-12">
          {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.TITLE') }}
        </h2>
        <p class="mt-2 max-w-3xl text-sm leading-6 text-n-slate-11">
          {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.DESCRIPTION') }}
        </p>
      </div>
      <div
        class="grid w-full min-w-0 gap-2 rounded-xl border border-n-weak bg-n-alpha-1 p-4 text-sm lg:min-w-72"
      >
        <div class="flex items-center justify-between gap-4">
          <span class="text-n-slate-10">
            {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.PROVIDER') }}
          </span>
          <span class="font-medium text-n-slate-12">
            {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.PROVIDER_VALUE') }}
          </span>
        </div>
        <div class="flex items-center justify-between gap-4">
          <span class="text-n-slate-10">
            {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.INBOX') }}
          </span>
          <span class="font-medium text-n-slate-12">{{ inbox?.name }}</span>
        </div>
        <div class="flex items-center justify-between gap-4">
          <span class="text-n-slate-10">
            {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.LAST_SYNC') }}
          </span>
          <span class="font-medium text-n-slate-12">
            {{ formattedLastSync }}
          </span>
        </div>
      </div>
    </section>

    <section class="grid gap-4 md:grid-cols-3">
      <button
        v-for="card in cards"
        :key="card.label"
        type="button"
        class="group min-h-36 rounded-2xl border border-n-weak bg-n-alpha-1 p-5 text-left transition hover:border-n-strong hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="emit('openTab', card.tab)"
      >
        <div class="flex items-start justify-between">
          <span
            class="flex size-10 items-center justify-center rounded-xl"
            :class="card.tone"
          >
            <span class="size-5" :class="card.icon" aria-hidden="true" />
          </span>
          <span
            class="i-lucide-arrow-up-right size-4 text-n-slate-9 transition group-hover:text-n-blue-11"
            aria-hidden="true"
          />
        </div>
        <div class="mt-4 text-2xl font-semibold text-n-slate-12">
          {{ card.value }}
        </div>
        <div class="mt-1 text-sm font-medium text-n-slate-12">
          {{ card.label }}
        </div>
        <div class="mt-1 text-xs text-n-slate-10">{{ card.secondary }}</div>
      </button>
    </section>

    <section class="grid gap-4 lg:grid-cols-2">
      <div class="rounded-2xl border border-n-weak bg-n-alpha-1 p-5">
        <h3
          class="flex items-center gap-2 text-base font-semibold text-n-slate-12"
        >
          <span
            class="i-lucide-clock-3 size-4 text-n-blue-11"
            aria-hidden="true"
          />
          {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.WINDOW.TITLE') }}
        </h3>
        <div class="mt-4 space-y-3 text-sm">
          <div class="flex gap-3">
            <span
              class="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full bg-n-teal-3 text-xs font-semibold text-n-teal-11"
            >
              {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.WINDOW.STEP_ONE') }}
            </span>
            <p class="leading-6 text-n-slate-11">
              {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.WINDOW.INBOUND') }}
            </p>
          </div>
          <div class="flex gap-3">
            <span
              class="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full bg-n-blue-3 text-xs font-semibold text-n-blue-11"
            >
              {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.WINDOW.STEP_TWO') }}
            </span>
            <p class="leading-6 text-n-slate-11">
              {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.WINDOW.OPEN') }}
            </p>
          </div>
          <div class="flex gap-3">
            <span
              class="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full bg-n-amber-3 text-xs font-semibold text-n-amber-11"
            >
              {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.WINDOW.STEP_THREE') }}
            </span>
            <p class="leading-6 text-n-slate-11">
              {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.WINDOW.CLOSED') }}
            </p>
          </div>
        </div>
      </div>

      <div class="rounded-2xl border border-n-weak bg-n-alpha-1 p-5">
        <h3
          class="flex items-center gap-2 text-base font-semibold text-n-slate-12"
        >
          <span
            class="i-lucide-mic-2 size-4 text-n-teal-11"
            aria-hidden="true"
          />
          {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.VOICE.TITLE') }}
        </h3>
        <p class="mt-3 text-sm leading-6 text-n-slate-11">
          {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.VOICE.DESCRIPTION') }}
        </p>
        <div class="mt-4 rounded-xl border border-n-weak bg-n-alpha-2 p-4">
          <div class="flex items-center gap-3">
            <span
              class="flex size-9 items-center justify-center rounded-full bg-n-teal-9 text-white"
            >
              <span class="i-lucide-audio-lines size-4" aria-hidden="true" />
            </span>
            <div>
              <div class="text-sm font-medium text-n-slate-12">
                {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.VOICE.NATIVE') }}
              </div>
              <div class="text-xs text-n-slate-10">
                {{ t('WHATSAPP_CLOUD_STUDIO.OVERVIEW.VOICE.FORMAT') }}
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
