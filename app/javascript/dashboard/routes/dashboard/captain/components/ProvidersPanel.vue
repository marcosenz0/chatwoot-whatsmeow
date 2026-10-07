<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import AiToggleRow from './AiToggleRow.vue';
import AiModelSelect from './AiModelSelect.vue';

const props = defineProps({
  providers: { type: Object, required: true },
  credentials: { type: Array, default: () => [] },
  catalogs: { type: Object, default: () => ({}) },
  canEdit: { type: Boolean, default: false },
  busy: { type: String, default: '' },
});
const emit = defineEmits(['save', 'test', 'refresh']);
const { t } = useI18n();
const forms = ref({});
watch(
  () => props.credentials,
  () => {
    forms.value = Object.fromEntries(
      Object.entries(props.providers).map(([provider, defaults]) => {
        const saved = props.credentials.find(
          item => item.provider === provider
        );
        return [
          provider,
          {
            id: saved?.id,
            api_key: '',
            api_base: saved?.api_base || defaults.default_api_base,
            model: saved?.model || defaults.default_model,
            enabled: saved?.enabled ?? true,
            configured: saved?.configured || false,
          },
        ];
      })
    );
  },
  { immediate: true }
);
</script>

<template>
  <section class="mx-auto w-full max-w-4xl space-y-6">
    <div>
      <h2 class="text-xl font-semibold text-n-slate-12">
        {{ t('MARCOX_AI.PROVIDERS.TITLE') }}
      </h2>
      <p class="mt-2 text-sm text-n-slate-11">
        {{ t('MARCOX_AI.PROVIDERS.BODY') }}
      </p>
    </div>
    <article
      v-for="(form, provider) in forms"
      :key="provider"
      class="rounded-2xl border border-n-weak bg-n-solid-1 p-6"
    >
      <div class="mb-5 flex items-center justify-between gap-3">
        <div class="flex items-center gap-3">
          <span
            class="flex size-11 items-center justify-center rounded-xl bg-n-alpha-2 text-n-slate-12"
            ><span class="i-lucide-plug-zap size-5"
          /></span>
          <div>
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ t(`MARCOX_AI.PROVIDERS.${provider.toUpperCase()}`) }}
            </h3>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ t(`MARCOX_AI.PROVIDERS.${provider.toUpperCase()}_HINT`) }}
            </p>
          </div>
        </div>
        <span
          class="rounded-full px-3 py-1 text-xs font-medium"
          :class="
            form.configured && form.enabled
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
          >{{
            t(
              form.configured && form.enabled
                ? 'MARCOX_AI.PROVIDERS.CONNECTED'
                : 'MARCOX_AI.PROVIDERS.MISSING'
            )
          }}</span
        >
      </div>
      <form class="space-y-4" @submit.prevent="emit('save', provider, form)">
        <fieldset :disabled="!canEdit || busy === provider" class="space-y-4">
          <label class="block text-sm font-medium text-n-slate-12"
            >{{ t('MARCOX_AI.PROVIDERS.KEY')
            }}<input
              v-model="form.api_key"
              type="password"
              autocomplete="new-password"
              :placeholder="
                t(
                  form.configured
                    ? 'MARCOX_AI.PROVIDERS.KEY_SAVED'
                    : 'MARCOX_AI.PROVIDERS.KEY_PLACEHOLDER'
                )
              "
              class="mt-2 !mb-0 h-10 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 font-mono text-sm"
          /></label>
          <div class="grid gap-4 sm:grid-cols-2">
            <label class="block text-sm font-medium text-n-slate-12"
              >{{ t('MARCOX_AI.PROVIDERS.DEFAULT_MODEL')
              }}<AiModelSelect
                v-model="form.model"
                class="mt-2"
                :models="catalogs[provider]?.models || []"
            /></label>
            <div class="pt-6">
              <AiToggleRow
                v-model="form.enabled"
                :label="t('MARCOX_AI.PROVIDERS.ENABLE')"
              />
            </div>
          </div>
          <details class="text-sm text-n-slate-11">
            <summary class="cursor-pointer">
              {{ t('MARCOX_AI.PROVIDERS.ADVANCED') }}
            </summary>
            <label class="mt-3 block"
              >{{ t('MARCOX_AI.PROVIDERS.ENDPOINT')
              }}<input
                v-model="form.api_base"
                type="url"
                required
                class="mt-2 !mb-0 h-10 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 text-sm"
            /></label>
          </details>
        </fieldset>
        <div
          class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak pt-4"
        >
          <div class="flex items-center gap-2 text-xs text-n-slate-11">
            <span>{{
              t(
                catalogs[provider]?.verified
                  ? 'MARCOX_AI.PROVIDERS.MODELS_VERIFIED'
                  : 'MARCOX_AI.PROVIDERS.MODELS_SUGGESTED'
              )
            }}</span
            ><Button
              v-if="canEdit && form.configured"
              size="xs"
              variant="ghost"
              color="slate"
              icon="i-lucide-refresh-cw"
              :aria-label="t('MARCOX_AI.REFRESH')"
              :disabled="busy === provider"
              @click="emit('refresh', provider)"
            />
          </div>
          <div v-if="canEdit" class="flex gap-2">
            <Button
              variant="outline"
              color="slate"
              :label="t('MARCOX_AI.PROVIDERS.TEST')"
              :disabled="!form.configured || !form.enabled || busy === provider"
              @click="emit('test', provider)"
            /><Button
              type="submit"
              :label="t('MARCOX_AI.PROVIDERS.CONNECT')"
              :is-loading="busy === provider"
              :disabled="
                (!form.configured && !form.api_key.trim()) || busy === provider
              "
            />
          </div>
        </div>
      </form>
    </article>
  </section>
</template>
