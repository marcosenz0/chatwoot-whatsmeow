<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from 'next/message/bubbles/Base.vue';
import FormattedContent from './FormattedContent.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import Icon from 'next/icon/Icon.vue';
import { MESSAGE_TYPES } from '../../constants';
import { useMessageContext } from '../../provider.js';
import { useTranslations } from 'dashboard/composables/useTranslations';

const { content, attachments, contentAttributes, messageType } =
  useMessageContext();
const { t } = useI18n();

const { hasTranslations, translationContent } =
  useTranslations(contentAttributes);

const renderOriginal = ref(false);
const showFullEditedContent = ref(false);

const EDITED_CONTENT_COLLAPSE_LENGTH = 280;
const EDITED_CONTENT_COLLAPSE_LINES = 5;

const getContentAttribute = (...keys) =>
  keys.find(key => contentAttributes.value?.[key] !== undefined);

const contentAttributeValue = (...keys) => {
  const key = getContentAttribute(...keys);
  return key ? contentAttributes.value[key] : null;
};

const textValue = value => (value ? value.toString() : '');

const originalEditedContent = computed(() =>
  textValue(
    contentAttributeValue(
      'whatsmeowOriginalContent',
      'whatsmeow_original_content'
    )
  )
);

const editedContent = computed(
  () =>
    textValue(
      contentAttributeValue(
        'whatsmeowEditedContent',
        'whatsmeow_edited_content'
      )
    ) || textValue(content.value)
);

const isWhatsmeowEdited = computed(
  () =>
    !!contentAttributeValue('whatsmeowEdited', 'whatsmeow_edited') &&
    !!editedContent.value
);

const editedTexts = computed(() =>
  [originalEditedContent.value, editedContent.value].filter(Boolean)
);

const shouldCollapseEditedContent = computed(() =>
  editedTexts.value.some(
    text =>
      text.length > EDITED_CONTENT_COLLAPSE_LENGTH ||
      text.split('\n').length > EDITED_CONTENT_COLLAPSE_LINES
  )
);

const editedTextClass = computed(() => ({
  'line-clamp-4':
    shouldCollapseEditedContent.value && !showFullEditedContent.value,
}));

const renderContent = computed(() => {
  if (renderOriginal.value) {
    return content.value;
  }

  if (hasTranslations.value) {
    return translationContent.value;
  }

  return content.value;
});

const isTemplate = computed(() => {
  return messageType.value === MESSAGE_TYPES.TEMPLATE;
});

const isEmpty = computed(() => {
  return !content.value && !attachments.value?.length;
});

const handleSeeOriginal = () => {
  renderOriginal.value = !renderOriginal.value;
};

const toggleEditedContent = () => {
  showFullEditedContent.value = !showFullEditedContent.value;
};
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="text">
    <div class="gap-3 flex flex-col">
      <span v-if="isEmpty" class="text-n-slate-11">
        {{ $t('CONVERSATION.NO_CONTENT') }}
      </span>
      <template v-if="isWhatsmeowEdited">
        <div v-if="originalEditedContent" class="space-y-1.5">
          <div
            class="inline-flex items-center gap-1 text-[11px] font-medium leading-4 text-n-slate-11"
          >
            <Icon icon="i-lucide-history" class="size-3 shrink-0" />
            <span>{{ t('CONVERSATION.MESSAGE_ORIGINAL') }}</span>
          </div>
          <div
            class="rounded-lg border border-n-weak bg-n-alpha-black1 px-3 py-2 opacity-80"
            :class="editedTextClass"
          >
            <FormattedContent :content="originalEditedContent" />
          </div>
        </div>
        <div class="space-y-1.5">
          <div
            class="inline-flex items-center gap-1 text-[11px] font-medium leading-4 text-n-slate-11"
          >
            <Icon icon="i-lucide-pencil" class="size-3 shrink-0" />
            <span>{{ t('CONVERSATION.MESSAGE_EDITED') }}</span>
          </div>
          <div :class="editedTextClass">
            <FormattedContent :content="editedContent" />
          </div>
        </div>
        <button
          v-if="shouldCollapseEditedContent"
          type="button"
          class="inline-flex w-fit items-center gap-1 text-xs font-medium text-n-blue-11 hover:text-n-blue-12"
          @click="toggleEditedContent"
        >
          <Icon
            :icon="
              showFullEditedContent
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
            class="size-3"
          />
          <span>
            {{
              showFullEditedContent
                ? t('CONVERSATION.SHOW_LESS')
                : t('CONVERSATION.SHOW_MORE')
            }}
          </span>
        </button>
      </template>
      <FormattedContent v-else-if="renderContent" :content="renderContent" />
      <TranslationToggle
        v-if="hasTranslations && !isWhatsmeowEdited"
        class="-mt-3"
        :showing-original="renderOriginal"
        @toggle="handleSeeOriginal"
      />
      <AttachmentChips :attachments="attachments" class="gap-2" />
      <template v-if="isTemplate">
        <div
          v-if="contentAttributes.submittedEmail"
          class="px-2 py-1 rounded-lg bg-n-alpha-3"
        >
          {{ contentAttributes.submittedEmail }}
        </div>
      </template>
    </div>
  </BaseBubble>
</template>

<style>
p:last-child {
  margin-bottom: 0;
}
</style>
