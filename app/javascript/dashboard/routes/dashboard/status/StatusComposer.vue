<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import WhatsmeowStatusesAPI from 'dashboard/api/whatsmeowStatuses';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import StatusDestinationSelector from './StatusDestinationSelector.vue';

const props = defineProps({
  inboxes: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['published']);

const { t } = useI18n();

const dialogRef = ref(null);
const fileInputRef = ref(null);
const mode = ref('text');
const content = ref('');
const background = ref('teal');
const font = ref('bold');
const mediaFile = ref(null);
const mediaPreviewUrl = ref('');
const isPublishing = ref(false);
const selectedInboxIds = ref([]);

let publishRequestToken = 0;

const BACKGROUNDS = [
  {
    value: 'teal',
    class: 'bg-n-teal-9',
    label: t('WHATSAPP_STATUS.COMPOSER.COLOR_TEAL'),
  },
  {
    value: 'blue',
    class: 'bg-n-blue-9',
    label: t('WHATSAPP_STATUS.COMPOSER.COLOR_BLUE'),
  },
  {
    value: 'violet',
    class: 'bg-n-violet-9',
    label: t('WHATSAPP_STATUS.COMPOSER.COLOR_VIOLET'),
  },
  {
    value: 'amber',
    class: 'bg-n-amber-9',
    label: t('WHATSAPP_STATUS.COMPOSER.COLOR_AMBER'),
  },
  {
    value: 'ruby',
    class: 'bg-n-ruby-9',
    label: t('WHATSAPP_STATUS.COMPOSER.COLOR_RUBY'),
  },
  {
    value: 'slate',
    class: 'bg-n-slate-11',
    label: t('WHATSAPP_STATUS.COMPOSER.COLOR_SLATE'),
  },
];

const FONT_CLASSES = {
  system: 'font-normal',
  bold: 'font-bold',
  serif: 'font-serif',
  modern: 'font-medium tracking-wide',
  mono: 'font-mono',
};

const fontOptions = computed(() => [
  { value: 'system', label: t('WHATSAPP_STATUS.COMPOSER.FONT_SYSTEM') },
  { value: 'bold', label: t('WHATSAPP_STATUS.COMPOSER.FONT_BOLD') },
  { value: 'serif', label: t('WHATSAPP_STATUS.COMPOSER.FONT_SERIF') },
  { value: 'modern', label: t('WHATSAPP_STATUS.COMPOSER.FONT_MODERN') },
  { value: 'mono', label: t('WHATSAPP_STATUS.COMPOSER.FONT_MONO') },
]);

const previewBackgroundClass = computed(
  () =>
    BACKGROUNDS.find(option => option.value === background.value)?.class ||
    BACKGROUNDS[0].class
);
const previewFontClass = computed(() => FONT_CLASSES[font.value]);
const isVideo = computed(() => mediaFile.value?.type.startsWith('video/'));
const connectedInboxIds = computed(() =>
  props.inboxes
    .filter(inbox => (inbox.channel?.status || inbox.status) === 'connected')
    .map(inbox => inbox.id)
);
const canPublish = computed(
  () =>
    selectedInboxIds.value.length > 0 &&
    (mode.value === 'text'
      ? Boolean(content.value.trim())
      : Boolean(mediaFile.value))
);

const revokeMediaPreview = () => {
  if (mediaPreviewUrl.value) URL.revokeObjectURL(mediaPreviewUrl.value);
  mediaPreviewUrl.value = '';
};

const clearMedia = () => {
  revokeMediaPreview();
  mediaFile.value = null;
  if (fileInputRef.value) fileInputRef.value.value = '';
};

const resetForm = () => {
  publishRequestToken += 1;
  mode.value = 'text';
  content.value = '';
  background.value = 'teal';
  font.value = 'bold';
  selectedInboxIds.value = [];
  clearMedia();
  isPublishing.value = false;
};

const open = (inboxIds = []) => {
  const requestedInboxIds = inboxIds.map(Number);
  const availableInboxIds = new Set(connectedInboxIds.value);
  selectedInboxIds.value = requestedInboxIds.length
    ? requestedInboxIds.filter(id => availableInboxIds.has(id))
    : connectedInboxIds.value;
  dialogRef.value?.open();
};

const openFilePicker = () => fileInputRef.value?.click();

const onFileSelected = event => {
  const [file] = event.target.files;
  if (!file) return;

  if (!file.type.startsWith('image/') && !file.type.startsWith('video/')) {
    useAlert(t('WHATSAPP_STATUS.COMPOSER.INVALID_FILE'));
    clearMedia();
    return;
  }

  revokeMediaPreview();
  mediaFile.value = file;
  mediaPreviewUrl.value = URL.createObjectURL(file);
};

const publish = async () => {
  if (!canPublish.value || isPublishing.value) return;

  publishRequestToken += 1;
  const requestToken = publishRequestToken;

  isPublishing.value = true;
  try {
    const publishRequests = selectedInboxIds.value.map(inboxId => {
      const formData = new FormData();
      formData.append('inbox_id', String(inboxId));
      formData.append('content', content.value.trim());
      formData.append('background', background.value);
      formData.append('font', font.value);
      if (mode.value === 'media') formData.append('media', mediaFile.value);
      return WhatsmeowStatusesAPI.publish(formData);
    });
    const results = await Promise.allSettled(publishRequests);
    if (requestToken !== publishRequestToken) return;

    const publishedStatuses = results
      .filter(result => result.status === 'fulfilled')
      .map(result => result.value.data.payload);
    const failedResults = results.filter(
      result => result.status === 'rejected'
    );

    if (publishedStatuses.length) emit('published', publishedStatuses);

    if (failedResults.length === results.length) {
      const [firstFailure] = failedResults;
      useAlert(
        firstFailure.reason?.response?.data?.message ||
          t('WHATSAPP_STATUS.COMPOSER.ERROR')
      );
      return;
    }

    if (failedResults.length) {
      useAlert(
        t('WHATSAPP_STATUS.COMPOSER.PARTIAL_ERROR', {
          published: publishedStatuses.length,
          failed: failedResults.length,
        })
      );
    } else {
      useAlert(
        t('WHATSAPP_STATUS.PUBLISHED_COUNT', {
          count: publishedStatuses.length,
        })
      );
    }
    dialogRef.value?.close();
  } catch (error) {
    if (requestToken !== publishRequestToken) return;
    useAlert(
      error.response?.data?.message || t('WHATSAPP_STATUS.COMPOSER.ERROR')
    );
  } finally {
    if (requestToken === publishRequestToken) isPublishing.value = false;
  }
};

onBeforeUnmount(() => {
  publishRequestToken += 1;
  revokeMediaPreview();
});

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :title="t('WHATSAPP_STATUS.COMPOSER.TITLE')"
    :description="t('WHATSAPP_STATUS.COMPOSER.DESCRIPTION')"
    :confirm-button-label="t('WHATSAPP_STATUS.COMPOSER.PUBLISH')"
    :disable-confirm-button="!canPublish"
    :is-loading="isPublishing"
    @close="resetForm"
    @confirm="publish"
  >
    <StatusDestinationSelector v-model="selectedInboxIds" :inboxes="inboxes" />

    <div class="flex rounded-xl bg-n-alpha-2 p-1" role="tablist">
      <button
        type="button"
        role="tab"
        class="flex min-h-11 flex-1 items-center justify-center gap-2 rounded-lg px-4 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          mode === 'text'
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
        "
        :aria-selected="mode === 'text'"
        @click="mode = 'text'"
      >
        <Icon icon="i-lucide-type" class="size-4" />
        {{ t('WHATSAPP_STATUS.COMPOSER.TEXT_TAB') }}
      </button>
      <button
        type="button"
        role="tab"
        class="flex min-h-11 flex-1 items-center justify-center gap-2 rounded-lg px-4 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          mode === 'media'
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
        "
        :aria-selected="mode === 'media'"
        @click="mode = 'media'"
      >
        <Icon icon="i-lucide-image" class="size-4" />
        {{ t('WHATSAPP_STATUS.COMPOSER.MEDIA_TAB') }}
      </button>
    </div>

    <template v-if="mode === 'text'">
      <div
        class="flex aspect-[9/11] max-h-80 items-center justify-center overflow-hidden rounded-2xl p-8 text-white shadow-inner transition-colors motion-reduce:transition-none"
        :class="previewBackgroundClass"
      >
        <p
          class="mb-0 whitespace-pre-wrap break-words text-center text-2xl leading-relaxed"
          :class="previewFontClass"
        >
          {{ content || t('WHATSAPP_STATUS.COMPOSER.TEXT_PLACEHOLDER') }}
        </p>
      </div>

      <div class="flex flex-col gap-2">
        <label
          for="whatsmeow-status-text"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('WHATSAPP_STATUS.COMPOSER.TEXT_LABEL') }}
        </label>
        <textarea
          id="whatsmeow-status-text"
          v-model="content"
          maxlength="700"
          rows="3"
          class="reset-base min-h-24 w-full resize-none rounded-lg border-0 bg-n-alpha-black2 px-3 py-2.5 text-base text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors placeholder:text-n-slate-10 hover:outline-n-slate-6 focus:outline-n-brand"
          :placeholder="t('WHATSAPP_STATUS.COMPOSER.TEXT_PLACEHOLDER')"
        />
      </div>

      <fieldset class="flex flex-col gap-2">
        <legend class="mb-2 text-sm font-medium text-n-slate-12">
          {{ t('WHATSAPP_STATUS.COMPOSER.BACKGROUND') }}
        </legend>
        <div class="flex flex-wrap gap-3">
          <button
            v-for="option in BACKGROUNDS"
            :key="option.value"
            type="button"
            class="size-11 rounded-full border-2 border-n-solid-1 outline outline-1 outline-n-weak transition-transform hover:scale-105 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand motion-reduce:transition-none"
            :class="[
              option.class,
              {
                'ring-2 ring-n-brand ring-offset-2 ring-offset-n-solid-1':
                  background === option.value,
              },
            ]"
            :aria-label="option.label"
            :aria-pressed="background === option.value"
            @click="background = option.value"
          />
        </div>
      </fieldset>

      <div class="flex flex-col gap-2">
        <label
          for="whatsmeow-status-font"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('WHATSAPP_STATUS.COMPOSER.FONT') }}
        </label>
        <select
          id="whatsmeow-status-font"
          v-model="font"
          class="reset-base min-h-11 w-full rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak hover:outline-n-slate-6 focus:outline-n-brand"
        >
          <option
            v-for="option in fontOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
      </div>
    </template>

    <template v-else>
      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('WHATSAPP_STATUS.COMPOSER.MEDIA_LABEL') }}
        </span>
        <button
          v-if="!mediaPreviewUrl"
          type="button"
          class="flex min-h-52 w-full flex-col items-center justify-center gap-3 rounded-2xl border border-dashed border-n-strong bg-n-alpha-2 p-6 text-center text-n-slate-11 transition-colors hover:border-n-brand hover:bg-n-brand/5 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="openFilePicker"
        >
          <span
            class="flex size-12 items-center justify-center rounded-full bg-n-brand/10 text-n-blue-11"
          >
            <Icon icon="i-lucide-upload" class="size-5" />
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('WHATSAPP_STATUS.COMPOSER.CHOOSE_MEDIA') }}
          </span>
          <span class="max-w-sm text-xs leading-5">
            {{ t('WHATSAPP_STATUS.COMPOSER.MEDIA_HELP') }}
          </span>
        </button>

        <div
          v-else
          class="relative flex max-h-80 min-h-52 items-center justify-center overflow-hidden rounded-2xl bg-black"
        >
          <video
            v-if="isVideo"
            :src="mediaPreviewUrl"
            controls
            class="max-h-80 w-full object-contain"
          />
          <img
            v-else
            :src="mediaPreviewUrl"
            :alt="t('WHATSAPP_STATUS.COMPOSER.PREVIEW_ALT')"
            class="max-h-80 w-full object-contain"
          />
          <Button
            icon="i-lucide-trash-2"
            type="button"
            color="ruby"
            size="lg"
            class="absolute right-3 top-3 shadow-lg"
            :aria-label="t('WHATSAPP_STATUS.COMPOSER.REMOVE_MEDIA')"
            @click="clearMedia"
          />
        </div>

        <Button
          v-if="mediaPreviewUrl"
          type="button"
          variant="faded"
          color="slate"
          icon="i-lucide-refresh-cw"
          class="self-start"
          :label="t('WHATSAPP_STATUS.COMPOSER.CHANGE_MEDIA')"
          @click="openFilePicker"
        />

        <input
          ref="fileInputRef"
          type="file"
          accept="image/jpeg,image/png,image/webp,video/*"
          class="hidden"
          @change="onFileSelected"
        />
      </div>

      <div class="flex flex-col gap-2">
        <label
          for="whatsmeow-status-caption"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ t('WHATSAPP_STATUS.COMPOSER.CAPTION_LABEL') }}
        </label>
        <textarea
          id="whatsmeow-status-caption"
          v-model="content"
          maxlength="700"
          rows="2"
          class="reset-base min-h-20 w-full resize-none rounded-lg border-0 bg-n-alpha-black2 px-3 py-2.5 text-base text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors placeholder:text-n-slate-10 hover:outline-n-slate-6 focus:outline-n-brand"
          :placeholder="t('WHATSAPP_STATUS.COMPOSER.CAPTION_PLACEHOLDER')"
        />
      </div>
    </template>
  </Dialog>
</template>
