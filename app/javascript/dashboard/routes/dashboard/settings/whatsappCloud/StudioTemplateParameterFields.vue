<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import {
  templateComponent,
  templateHeader,
  templateVariableKeys,
} from './templateParameterUtils';

const props = defineProps({
  template: { type: Object, required: true },
  modelValue: { type: Object, default: () => ({}) },
  allowLiquid: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const cloneParameters = () =>
  JSON.parse(JSON.stringify(props.modelValue || {}));

const header = computed(() => templateHeader(props.template));
const bodyVariableKeys = computed(() =>
  templateVariableKeys(templateComponent(props.template, 'BODY')?.text)
);
const editableButtons = computed(() => {
  const templateButtons =
    templateComponent(props.template, 'BUTTONS')?.buttons || [];
  const buttons = Array.isArray(props.modelValue.buttons)
    ? props.modelValue.buttons
    : [];
  return buttons
    .map((button, parameterIndex) => ({
      ...button,
      parameterIndex,
      title: templateButtons[button.index]?.text || '',
    }))
    .filter(button => ['url', 'copy_code'].includes(button.type));
});
const hasFields = computed(
  () =>
    header.value.isMedia ||
    header.value.variableKeys.length ||
    bodyVariableKeys.value.length ||
    editableButtons.value.length
);

const updateSection = (section, key, value) => {
  const parameters = cloneParameters();
  parameters[section] ||= {};
  parameters[section][key] = value;
  emit('update:modelValue', parameters);
};

const updateButton = (parameterIndex, value) => {
  const parameters = cloneParameters();
  parameters.buttons[parameterIndex].parameter = value;
  emit('update:modelValue', parameters);
};

const buttonParameterLabel = button =>
  button.type === 'copy_code'
    ? t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.COPY_CODE', {
        button: button.title,
      })
    : t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.URL_BUTTON', {
        button: button.title,
      });

const parameterHint = computed(() =>
  props.allowLiquid
    ? t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.LIQUID_HINT')
    : t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.STATIC_HINT')
);
</script>

<template>
  <div v-show="hasFields" class="grid gap-3">
    <label
      v-if="header.isMedia"
      class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
    >
      {{
        t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.MEDIA_URL', {
          format: header.format,
        })
      }}
      <input
        required
        type="text"
        :value="modelValue.header?.media_url || ''"
        class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
        :placeholder="
          t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.MEDIA_URL_PLACEHOLDER')
        "
        @input="updateSection('header', 'media_url', $event.target.value)"
      />
    </label>

    <label
      v-if="header.format === 'DOCUMENT'"
      class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
    >
      {{ t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.MEDIA_NAME') }}
      <input
        type="text"
        :value="modelValue.header?.media_name || ''"
        class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
        :placeholder="
          t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.MEDIA_NAME_PLACEHOLDER')
        "
        @input="updateSection('header', 'media_name', $event.target.value)"
      />
    </label>

    <label
      v-for="variableKey in header.variableKeys"
      :key="`header-${variableKey}`"
      class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
    >
      {{
        t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.HEADER_VARIABLE', {
          variable: variableKey,
        })
      }}
      <input
        required
        type="text"
        :value="modelValue.header?.[variableKey] || ''"
        class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
        :placeholder="
          t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.VALUE_PLACEHOLDER')
        "
        @input="updateSection('header', variableKey, $event.target.value)"
      />
    </label>

    <label
      v-for="variableKey in bodyVariableKeys"
      :key="`body-${variableKey}`"
      class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
    >
      {{
        t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.BODY_VARIABLE', {
          variable: variableKey,
        })
      }}
      <input
        required
        type="text"
        :value="modelValue.body?.[variableKey] || ''"
        class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
        :placeholder="
          t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.VALUE_PLACEHOLDER')
        "
        @input="updateSection('body', variableKey, $event.target.value)"
      />
    </label>

    <label
      v-for="button in editableButtons"
      :key="`${button.type}-${button.index}`"
      class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
    >
      {{ buttonParameterLabel(button) }}
      <input
        required
        type="text"
        :maxlength="button.type === 'copy_code' ? 15 : undefined"
        :value="button.parameter || ''"
        class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
        :placeholder="
          t('WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.VALUE_PLACEHOLDER')
        "
        @input="updateButton(button.parameterIndex, $event.target.value)"
      />
    </label>

    <p class="text-xs leading-5 text-n-slate-9">
      {{ parameterHint }}
    </p>
  </div>
</template>
