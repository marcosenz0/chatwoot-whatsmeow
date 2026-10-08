<script setup>
import { computed, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'next/button/Button.vue';
import MenuSelect from 'dashboard/routes/dashboard/captain/components/AiSelect.vue';

const props = defineProps({
  profile: { type: Object, required: true },
  saving: { type: Boolean, default: false },
});
const emit = defineEmits(['save']);
const { t } = useI18n();
const dayNames = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const toTime = value =>
  `${String(Math.floor(Number(value || 0) / 60)).padStart(2, '0')}:${String(Number(value || 0) % 60).padStart(2, '0')}`;
const toMinutes = value => {
  const [hour, minute] = value.split(':').map(Number);
  return hour * 60 + minute;
};
const form = reactive({
  address: props.profile.address || '',
  email: props.profile.email || '',
  description: props.profile.description || '',
  websites: [
    props.profile.websites?.[0] || '',
    props.profile.websites?.[1] || '',
  ],
  timezone:
    props.profile.hours?.timezone ||
    Intl.DateTimeFormat().resolvedOptions().timeZone,
  days: dayNames.map(day => {
    const entry = props.profile.hours?.days?.find(item => item.day === day);
    return {
      day,
      mode: entry?.mode || 'closed',
      open: entry ? toTime(entry.open) : '09:00',
      close: entry ? toTime(entry.close) : '18:00',
    };
  }),
});
const hoursChanged = computed(
  () =>
    JSON.stringify(form.days) !==
      JSON.stringify(
        dayNames.map(day => {
          const entry = props.profile.hours?.days?.find(
            item => item.day === day
          );
          return {
            day,
            mode: entry?.mode || 'closed',
            open: entry ? toTime(entry.open) : '09:00',
            close: entry ? toTime(entry.close) : '18:00',
          };
        })
      ) ||
    form.timezone !==
      (props.profile.hours?.timezone ||
        Intl.DateTimeFormat().resolvedOptions().timeZone)
);
const modes = computed(() =>
  ['closed', 'specific_hours', 'open_24h', 'appointment_only'].map(value => ({
    value,
    label: t(`WHATSAPP_PROFILE.MODES.${value}`),
  }))
);
const timezones = computed(() =>
  [...new Set([form.timezone, ...Intl.supportedValuesOf('timeZone')])].map(
    value => ({ value, label: value })
  )
);
const save = () => {
  const business = {
    address: form.address,
    email: form.email,
    description: form.description,
    websites: form.websites.map(value => value.trim()).filter(Boolean),
  };
  if (hoursChanged.value)
    business.hours = {
      timezone: form.timezone,
      days: form.days
        .filter(day => day.mode !== 'closed')
        .map(day => ({
          day: day.day,
          mode: day.mode,
          open: day.mode === 'specific_hours' ? toMinutes(day.open) : 0,
          close: day.mode === 'specific_hours' ? toMinutes(day.close) : 0,
        })),
    };
  emit('save', business);
};
</script>

<template>
  <form class="space-y-5" @submit.prevent="save">
    <h3 class="text-base font-medium text-n-slate-12">
      {{ t('WHATSAPP_PROFILE.BUSINESS_TITLE') }}
    </h3>
    <label class="block text-sm font-medium text-n-slate-12">
      {{ t('WHATSAPP_PROFILE.DESCRIPTION') }}
      <textarea
        v-model="form.description"
        maxlength="1024"
        rows="3"
        :disabled="saving"
        class="!mb-0 mt-2 w-full rounded-lg bg-n-solid-1 text-sm"
      />
    </label>
    <label class="block text-sm font-medium text-n-slate-12">
      {{ t('WHATSAPP_PROFILE.ADDRESS') }}
      <input
        v-model="form.address"
        maxlength="512"
        :disabled="saving"
        class="!mb-0 mt-2 w-full rounded-lg bg-n-solid-1 text-sm"
      />
    </label>
    <label class="block text-sm font-medium text-n-slate-12">
      {{ t('WHATSAPP_PROFILE.EMAIL') }}
      <input
        v-model="form.email"
        type="email"
        maxlength="320"
        :disabled="saving"
        class="!mb-0 mt-2 w-full rounded-lg bg-n-solid-1 text-sm"
      />
    </label>
    <div class="grid gap-4 md:grid-cols-2">
      <label
        v-for="(_, index) in form.websites"
        :key="index"
        class="block text-sm font-medium text-n-slate-12"
      >
        {{ t('WHATSAPP_PROFILE.WEBSITE', { number: index + 1 }) }}
        <input
          v-model="form.websites[index]"
          type="url"
          maxlength="2048"
          :disabled="saving"
          class="!mb-0 mt-2 w-full rounded-lg bg-n-solid-1 text-sm"
        />
      </label>
    </div>
    <div v-if="profile.categories?.length" class="space-y-1 text-sm">
      <span class="font-medium text-n-slate-12">{{
        t('WHATSAPP_PROFILE.CATEGORY')
      }}</span>
      <p class="mb-0 text-n-slate-11">
        {{ profile.categories.map(category => category.Name).join(', ') }}
      </p>
      <p class="mb-0 text-xs text-n-slate-11">
        {{ t('WHATSAPP_PROFILE.CATEGORY_HELP') }}
      </p>
    </div>
    <h4 class="text-sm font-medium text-n-slate-12">
      {{ t('WHATSAPP_PROFILE.HOURS') }}
    </h4>
    <MenuSelect
      v-model="form.timezone"
      :label="t('WHATSAPP_PROFILE.TIMEZONE')"
      :options="timezones"
      searchable
      :disabled="saving"
    />
    <div
      v-for="day in form.days"
      :key="day.day"
      class="grid items-center gap-3 border-b border-n-weak pb-3 sm:grid-cols-[6rem_minmax(0,1fr)]"
    >
      <span class="text-sm text-n-slate-12">{{
        t(`WHATSAPP_PROFILE.DAYS.${day.day}`)
      }}</span>
      <div class="flex min-w-0 flex-wrap items-center gap-3">
        <MenuSelect
          v-model="day.mode"
          :label="
            t('WHATSAPP_PROFILE.DAY_MODE', {
              day: t(`WHATSAPP_PROFILE.DAYS.${day.day}`),
            })
          "
          :options="modes"
          :disabled="saving"
          class="!w-48"
        />
        <template v-if="day.mode === 'specific_hours'">
          <input
            v-model="day.open"
            type="time"
            required
            :aria-label="
              t('WHATSAPP_PROFILE.OPENS', {
                day: t(`WHATSAPP_PROFILE.DAYS.${day.day}`),
              })
            "
            :disabled="saving"
            class="!mb-0 !w-28 rounded-lg bg-n-solid-1 text-sm"
          />
          <span class="text-n-slate-11">{{ t('WHATSAPP_PROFILE.UNTIL') }}</span>
          <input
            v-model="day.close"
            type="time"
            required
            :aria-label="
              t('WHATSAPP_PROFILE.CLOSES', {
                day: t(`WHATSAPP_PROFILE.DAYS.${day.day}`),
              })
            "
            :disabled="saving"
            class="!mb-0 !w-28 rounded-lg bg-n-solid-1 text-sm"
          />
        </template>
      </div>
    </div>
    <Button
      type="submit"
      :label="t('WHATSAPP_PROFILE.SAVE_BUSINESS')"
      :is-loading="saving"
      :disabled="saving"
      icon="i-lucide-check"
    />
  </form>
</template>
