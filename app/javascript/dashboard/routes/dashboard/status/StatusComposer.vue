<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import WhatsmeowStatusesAPI from 'dashboard/api/whatsmeowStatuses';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DropdownBody from 'dashboard/components-next/dropdown-menu/base/DropdownBody.vue';
import DropdownContainer from 'dashboard/components-next/dropdown-menu/base/DropdownContainer.vue';
import DropdownItem from 'dashboard/components-next/dropdown-menu/base/DropdownItem.vue';
import DropdownSection from 'dashboard/components-next/dropdown-menu/base/DropdownSection.vue';
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
const textTabRef = ref(null);
const mediaTabRef = ref(null);
const mode = ref('text');
const content = ref('');
const background = ref('teal');
const font = ref('bold');
const mediaFile = ref(null);
const mediaPreviewUrl = ref('');
const isPublishing = ref(false);
const selectedInboxIds = ref([]);
const publicationId = ref(crypto.randomUUID());

let publishRequestToken = 0;
let mediaSelectionVersion = 0;
let lastAttemptFingerprint = '';

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
const selectedFontLabel = computed(
  () =>
    fontOptions.value.find(option => option.value === font.value)?.label ||
    fontOptions.value[0].label
);
const isVideo = computed(() => mediaFile.value?.type.startsWith('video/'));
const isAudio = computed(() => mediaFile.value?.type.startsWith('audio/'));
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
  mediaSelectionVersion = 0;
  lastAttemptFingerprint = '';
  publicationId.value = crypto.randomUUID();
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

const selectFont = value => {
  font.value = value;
};

const selectMode = (value, { focus = false } = {}) => {
  mode.value = value;
  if (focus) {
    const target = value === 'text' ? textTabRef.value : mediaTabRef.value;
    target?.focus();
  }
};

const onTabKeydown = event => {
  let targetMode = { Home: 'text', End: 'media' }[event.key];
  if (['ArrowLeft', 'ArrowRight'].includes(event.key)) {
    targetMode = mode.value === 'text' ? 'media' : 'text';
  }
  if (!targetMode) return;

  event.preventDefault();
  selectMode(targetMode, { focus: true });
};

const onFileSelected = event => {
  const [file] = event.target.files;
  if (!file) return;

  if (
    !file.type.startsWith('image/') &&
    !file.type.startsWith('video/') &&
    !file.type.startsWith('audio/')
  ) {
    useAlert(t('WHATSAPP_STATUS.COMPOSER.INVALID_FILE'));
    clearMedia();
    return;
  }

  revokeMediaPreview();
  mediaSelectionVersion += 1;
  mediaFile.value = file;
  mediaPreviewUrl.value = URL.createObjectURL(file);
};

const currentPayloadFingerprint = () =>
  JSON.stringify({
    inboxIds: selectedInboxIds.value.map(Number).sort((a, b) => a - b),
    mode: mode.value,
    content: content.value.trim(),
    background: background.value,
    font: font.value,
    media:
      mode.value === 'media' && mediaFile.value
        ? {
            name: mediaFile.value.name,
            size: mediaFile.value.size,
            type: mediaFile.value.type,
            lastModified: mediaFile.value.lastModified,
            selection: mediaSelectionVersion,
          }
        : null,
  });

const publish = async () => {
  if (!canPublish.value || isPublishing.value) return;

  publishRequestToken += 1;
  const requestToken = publishRequestToken;
  const attemptFingerprint = currentPayloadFingerprint();
  if (lastAttemptFingerprint && lastAttemptFingerprint !== attemptFingerprint) {
    publicationId.value = crypto.randomUUID();
  }
  lastAttemptFingerprint = attemptFingerprint;

  isPublishing.value = true;
  try {
    const formData = new FormData();
    selectedInboxIds.value.forEach(inboxId => {
      formData.append('inbox_ids[]', String(inboxId));
    });
    formData.append('publication_id', publicationId.value);
    formData.append('content', content.value.trim());
    formData.append('background', background.value);
    formData.append('font', font.value);
    if (mode.value === 'media') formData.append('media', mediaFile.value);

    const response = await WhatsmeowStatusesAPI.publish(formData);
    if (requestToken !== publishRequestToken) return;

    const queuedStatuses = Array.isArray(response.data.payload)
      ? response.data.payload
      : [response.data.payload].filter(Boolean);
    emit('published', queuedStatuses);
    useAlert(
      t('WHATSAPP_STATUS.COMPOSER.QUEUED_COUNT', {
        count: queuedStatuses.length || selectedInboxIds.value.length,
      })
    );
    dialogRef.value?.close();
  } catch {
    if (requestToken !== publishRequestToken) return;
    useAlert(t('WHATSAPP_STATUS.COMPOSER.ERROR'));
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
    :prevent-close="isPublishing"
    @close="resetForm"
    @confirm="publish"
  >
    <StatusDestinationSelector v-model="selectedInboxIds" :inboxes="inboxes" />

    <div
      class="flex rounded-xl bg-n-alpha-2 p-1"
      role="tablist"
      aria-orientation="horizontal"
      @keydown="onTabKeydown"
    >
      <button
        id="whatsmeow-status-text-tab"
        ref="textTabRef"
        type="button"
        role="tab"
        class="flex min-h-11 flex-1 items-center justify-center gap-2 rounded-lg px-4 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          mode === 'text'
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
        "
        :aria-selected="mode === 'text'"
        aria-controls="whatsmeow-status-text-panel"
        :tabindex="mode === 'text' ? 0 : -1"
        @click="selectMode('text')"
      >
        <Icon icon="i-lucide-type" class="size-4" />
        {{ t('WHATSAPP_STATUS.COMPOSER.TEXT_TAB') }}
      </button>
      <button
        id="whatsmeow-status-media-tab"
        ref="mediaTabRef"
        type="button"
        role="tab"
        class="flex min-h-11 flex-1 items-center justify-center gap-2 rounded-lg px-4 text-sm font-medium transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          mode === 'media'
            ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
        "
        :aria-selected="mode === 'media'"
        aria-controls="whatsmeow-status-media-panel"
        :tabindex="mode === 'media' ? 0 : -1"
        @click="selectMode('media')"
      >
        <Icon icon="i-lucide-image" class="size-4" />
        {{ t('WHATSAPP_STATUS.COMPOSER.MEDIA_TAB') }}
      </button>
    </div>

    <div
      v-if="mode === 'text'"
      id="whatsmeow-status-text-panel"
      role="tabpanel"
      aria-labelledby="whatsmeow-status-text-tab"
      class="flex flex-col gap-6"
    >
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
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('WHATSAPP_STATUS.COMPOSER.FONT') }}
        </span>
        <DropdownContainer class="w-full !space-y-0 [&>div]:w-full">
          <template #trigger="{ toggle, isOpen }">
            <button
              type="button"
              class="reset-base flex min-h-11 w-full items-center gap-3 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 text-left outline-none transition-colors hover:bg-n-alpha-1 focus-visible:border-n-brand focus-visible:ring-1 focus-visible:ring-n-brand"
              :class="{ 'border-n-brand bg-n-alpha-1': isOpen }"
              :aria-expanded="isOpen"
              :aria-label="t('WHATSAPP_STATUS.COMPOSER.FONT')"
              aria-haspopup="listbox"
              @click="toggle"
            >
              <span
                class="flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-12"
                aria-hidden="true"
              >
                <Icon icon="i-lucide-type" class="size-4" />
              </span>
              <span class="min-w-0 flex-1">
                <span
                  class="block truncate text-sm font-medium text-n-slate-12"
                >
                  {{ selectedFontLabel }}
                </span>
              </span>
              <Icon
                icon="i-lucide-chevron-down"
                class="size-4 flex-shrink-0 text-n-slate-10 transition-transform duration-200 motion-reduce:transition-none"
                :class="{ 'rotate-180': isOpen }"
              />
            </button>
          </template>

          <DropdownBody
            class="left-0 top-0 z-50 w-full min-w-[14rem] [&>ul]:!bg-n-solid-2 [&>ul]:!backdrop-blur-none"
          >
            <DropdownSection>
              <DropdownItem
                v-for="option in fontOptions"
                :key="option.value"
                :click="() => selectFont(option.value)"
                role="option"
                :aria-selected="font === option.value"
                class="rounded-lg hover:bg-n-alpha-2"
                :class="{
                  'bg-n-alpha-2': font === option.value,
                }"
              >
                <div class="flex min-h-10 w-full items-center gap-3">
                  <span
                    class="flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-slate-12"
                    aria-hidden="true"
                  >
                    <Icon icon="i-lucide-type" class="size-4" />
                  </span>
                  <span class="min-w-0 flex-1 truncate text-sm text-n-slate-12">
                    {{ option.label }}
                  </span>
                  <Icon
                    v-if="font === option.value"
                    icon="i-lucide-check"
                    class="size-4 flex-shrink-0 text-n-brand"
                  />
                </div>
              </DropdownItem>
            </DropdownSection>
          </DropdownBody>
        </DropdownContainer>
      </div>
    </div>

    <div
      v-else
      id="whatsmeow-status-media-panel"
      role="tabpanel"
      aria-labelledby="whatsmeow-status-media-tab"
      class="flex flex-col gap-6"
    >
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
          <div
            v-if="isAudio"
            class="flex h-52 w-full flex-col items-center justify-center gap-4 bg-n-slate-11 p-6"
          >
            <span
              class="flex size-14 items-center justify-center rounded-full bg-white/10 text-white"
            >
              <Icon icon="i-lucide-mic-2" class="size-6" />
            </span>
            <span class="text-sm font-medium text-white">
              {{ t('WHATSAPP_STATUS.COMPOSER.AUDIO_PREVIEW') }}
            </span>
            <audio :src="mediaPreviewUrl" controls class="w-full max-w-sm" />
          </div>
          <video
            v-else-if="isVideo"
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
          accept="image/jpeg,image/png,image/webp,video/*,audio/*"
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
    </div>
  </Dialog>
</template>
