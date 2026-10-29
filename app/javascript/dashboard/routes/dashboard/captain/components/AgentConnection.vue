<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  provider: { type: String, required: true },
  defaults: { type: Object, default: () => ({}) },
  credential: { type: Object, default: null },
  canEdit: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
  active: { type: Boolean, default: false },
});
const emit = defineEmits(['save', 'test', 'refresh', 'change']);
const { t } = useI18n();
const form = ref({});
const editing = ref(false);
const ready = computed(
  () => props.credential?.configured && props.credential?.enabled
);
watch(
  form,
  value =>
    emit('change', {
      ...value,
      provider: props.provider,
      dirty:
        !!value.api_key?.trim() ||
        (ready.value && value.api_base !== props.credential?.api_base),
    }),
  { deep: true }
);
watch(
  [
    () => props.provider,
    () => props.credential?.id,
    () => props.credential?.updated_at,
    () => props.credential?.configured,
    () => props.credential?.enabled,
  ],
  () => {
    form.value = {
      id: props.credential?.id,
      name: props.credential?.name || 'Principal',
      api_key: '',
      api_base: props.credential?.api_base || props.defaults.default_api_base,
      model: props.credential?.model || props.defaults.default_model,
      enabled: true,
    };
    editing.value = !ready.value;
  },
  { immediate: true }
);
</script>

<template>
  <section class="rounded-xl border border-n-weak bg-n-alpha-1">
    <div class="flex flex-wrap items-center justify-between gap-3 p-4">
      <div class="flex min-w-0 flex-1 items-center gap-3">
        <span
          :class="
            credential?.health?.state === 'error'
              ? 'i-lucide-circle-x text-n-ruby-11'
              : ready
                ? 'i-lucide-circle-check text-n-teal-11'
                : 'i-lucide-key-round text-n-slate-11'
          "
          class="size-5 shrink-0"
        />
        <div class="min-w-0">
          <p class="m-0 text-sm font-medium text-n-slate-12">
            {{
              t(
                credential?.health?.state === 'error'
                  ? 'MARCOX_AI.FALLBACK.FAILED'
                  : ready
                    ? 'MARCOX_AI.PROVIDERS.CONNECTED'
                    : 'MARCOX_AI.PROVIDERS.MISSING'
              )
            }}
          </p>
          <p v-if="active" class="m-0 mt-1 text-xs font-medium text-n-teal-11">
            {{ t('MARCOX_AI.FALLBACK.IN_USE') }}
          </p>
          <p
            v-if="credential?.health?.state === 'error'"
            class="m-0 mt-1 break-words text-xs text-n-ruby-11"
          >
            {{ credential.health.error }}
          </p>
          <p class="m-0 mt-1 text-xs text-n-slate-11">
            {{
              t('MARCOX_AI.PROVIDERS.IN_AGENT', {
                provider: t(`MARCOX_AI.PROVIDERS.${provider.toUpperCase()}`),
              })
            }}
          </p>
          <p
            v-if="credential?.source === 'integration'"
            class="m-0 mt-1 text-xs text-n-teal-11"
          >
            {{ t('MARCOX_AI.PROVIDERS.INTEGRATION_KEY') }}
          </p>
        </div>
      </div>
      <div v-if="canEdit && ready" class="flex items-center gap-1">
        <Button
          type="button"
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-refresh-cw"
          :aria-label="t('MARCOX_AI.REFRESH')"
          :disabled="busy"
          @click="emit('refresh')"
        />
        <Button
          type="button"
          variant="ghost"
          color="slate"
          size="sm"
          :label="t('MARCOX_AI.PROVIDERS.TEST')"
          :disabled="busy"
          @click="emit('test')"
        />
        <Button
          type="button"
          variant="ghost"
          color="slate"
          size="sm"
          :label="t('MARCOX_AI.PROVIDERS.EDIT_KEY')"
          :disabled="busy"
          @click="editing = !editing"
        />
      </div>
    </div>
    <div v-if="editing && canEdit" class="space-y-4 border-t border-n-weak p-4">
      <label class="block text-sm font-medium text-n-slate-12">
        {{ t('MARCOX_AI.PROVIDERS.KEY') }}
        <input
          v-model="form.api_key"
          type="password"
          autocomplete="new-password"
          :placeholder="
            t(
              credential?.configured
                ? 'MARCOX_AI.PROVIDERS.KEY_SAVED'
                : 'MARCOX_AI.PROVIDERS.KEY_PLACEHOLDER'
            )
          "
          class="reset-base !mb-0 mt-2 h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
        />
      </label>
      <p class="m-0 text-xs leading-5 text-n-slate-11">
        {{ t('MARCOX_AI.PROVIDERS.SHARED_KEY') }}
      </p>
      <details class="text-sm text-n-slate-11">
        <summary class="cursor-pointer">
          {{ t('MARCOX_AI.PROVIDERS.ADVANCED') }}
        </summary>
        <label class="mt-3 block"
          >{{ t('MARCOX_AI.PROVIDERS.ENDPOINT') }}
          <input
            v-model="form.api_base"
            type="url"
            class="reset-base !mb-0 mt-2 h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
          />
        </label>
      </details>
      <Button
        type="button"
        icon="i-lucide-key-round"
        :label="t('MARCOX_AI.PROVIDERS.CONNECT')"
        :is-loading="busy"
        :disabled="busy || (!credential?.configured && !form.api_key.trim())"
        @click="emit('save', form)"
      />
    </div>
  </section>
</template>
