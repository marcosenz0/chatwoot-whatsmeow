<script setup>
import { computed, ref } from 'vue';
import { DirectUpload } from 'activestorage';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { setDirectUploadAuthHeaders } from 'dashboard/helper/directUploadsHelper';

const props = defineProps({
  modelValue: { type: Object, required: true },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const fileInput = ref(null);
const isDragging = ref(false);
const isUploading = ref(false);
const uploadProgress = ref(0);

const mediaRules = {
  audio: {
    accept: 'audio/aac,audio/mp4,audio/mpeg,audio/amr,audio/ogg,audio/opus',
    types: [
      'audio/aac',
      'audio/mp4',
      'audio/mpeg',
      'audio/amr',
      'audio/ogg',
      'audio/opus',
    ],
    maxBytes: 16 * 1024 * 1024,
    icon: 'i-lucide-audio-lines',
  },
  image: {
    accept: 'image/jpeg,image/png',
    types: ['image/jpeg', 'image/png'],
    maxBytes: 5 * 1024 * 1024,
    icon: 'i-lucide-image',
  },
  video: {
    accept: 'video/mp4,video/3gpp',
    types: ['video/mp4', 'video/3gpp'],
    maxBytes: 16 * 1024 * 1024,
    icon: 'i-lucide-video',
  },
  document: {
    accept: '.txt,.csv,.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx',
    types: [
      'text/plain',
      'text/csv',
      'application/pdf',
      'application/msword',
      'application/vnd.ms-excel',
      'application/vnd.ms-powerpoint',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    ],
    maxBytes: 100 * 1024 * 1024,
    icon: 'i-lucide-file-text',
  },
  sticker: {
    accept: 'image/webp',
    types: ['image/webp'],
    maxBytes: 100 * 1024,
    icon: 'i-lucide-sticker',
  },
};

const mediaType = computed(() => props.modelValue.media_type || 'audio');
const rule = computed(() => mediaRules[mediaType.value]);
const hasFile = computed(() => Boolean(props.modelValue.blob_signed_id));
const isVoiceCapable = computed(() =>
  ['audio/ogg', 'audio/opus'].includes(props.modelValue.content_type)
);
const maximumSize = computed(() => {
  const bytes = rule.value.maxBytes;
  return bytes < 1024 * 1024
    ? `${Math.round(bytes / 1024)} KB`
    : `${Math.round(bytes / 1024 / 1024)} MB`;
});
const fileSize = computed(() => {
  const bytes = Number(props.modelValue.byte_size || 0);
  if (!bytes) return '';
  return bytes < 1024 * 1024
    ? `${Math.ceil(bytes / 1024)} KB`
    : `${(bytes / 1024 / 1024).toFixed(1)} MB`;
});

const updateConfig = values => {
  emit('update:modelValue', { ...props.modelValue, ...values });
};

const removeFile = () => {
  updateConfig({
    blob_signed_id: '',
    filename: '',
    content_type: '',
    byte_size: null,
    is_voice_message: false,
  });
  if (fileInput.value) fileInput.value.value = '';
};

const validateFile = file => {
  if (!rule.value.types.includes(file.type)) {
    useAlert(t('WHATSAPP_CLOUD_STUDIO.FLOWS.MEDIA.INVALID_FORMAT'));
    return false;
  }
  if (file.size > rule.value.maxBytes) {
    useAlert(
      t('WHATSAPP_CLOUD_STUDIO.FLOWS.MEDIA.SIZE_ERROR', {
        size: maximumSize.value,
      })
    );
    return false;
  }
  return true;
};

const uploadFile = file => {
  if (!file || isUploading.value || !validateFile(file)) return;
  isUploading.value = true;
  uploadProgress.value = 0;

  const upload = new DirectUpload(
    file,
    '/rails/active_storage/direct_uploads',
    {
      directUploadWillCreateBlobWithXHR: setDirectUploadAuthHeaders,
      directUploadWillStoreFileWithXHR: xhr => {
        xhr.upload.addEventListener('progress', event => {
          if (!event.lengthComputable) return;
          uploadProgress.value = Math.round((event.loaded / event.total) * 100);
        });
      },
    }
  );

  upload.create((error, blob) => {
    isUploading.value = false;
    if (error) {
      useAlert(t('WHATSAPP_CLOUD_STUDIO.FLOWS.MEDIA.UPLOAD_ERROR'));
      return;
    }
    updateConfig({
      blob_signed_id: blob.signed_id,
      filename: blob.filename || file.name,
      content_type: blob.content_type || file.type,
      byte_size: blob.byte_size || file.size,
      is_voice_message: false,
    });
  });
};

const onInput = event => uploadFile(event.target.files?.[0]);
const onDrop = event => {
  isDragging.value = false;
  uploadFile(event.dataTransfer?.files?.[0]);
};
</script>

<template>
  <div class="space-y-4">
    <input
      ref="fileInput"
      type="file"
      class="hidden"
      :accept="rule.accept"
      @change="onInput"
    />

    <div
      v-if="!hasFile"
      class="flex min-h-36 cursor-pointer flex-col items-center justify-center rounded-2xl border border-dashed px-4 py-5 text-center transition"
      :class="
        isDragging
          ? 'border-n-brand bg-n-blue-3'
          : 'border-n-strong bg-n-alpha-1 hover:border-n-brand hover:bg-n-alpha-2'
      "
      role="button"
      tabindex="0"
      @click="fileInput?.click()"
      @keydown.enter="fileInput?.click()"
      @dragenter.prevent="isDragging = true"
      @dragover.prevent="isDragging = true"
      @dragleave.prevent="isDragging = false"
      @drop.prevent="onDrop"
    >
      <span
        class="mb-3 flex size-10 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
      >
        <span class="size-5" :class="rule.icon" aria-hidden="true" />
      </span>
      <strong class="text-sm text-n-slate-12">
        {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.MEDIA.SELECT_FILE') }}
      </strong>
      <span class="mt-1 text-xs leading-5 text-n-slate-9">
        {{
          t('WHATSAPP_CLOUD_STUDIO.FLOWS.MEDIA.FILE_HINT', {
            size: maximumSize,
          })
        }}
      </span>
    </div>

    <div
      v-else
      class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-alpha-2 p-3"
    >
      <span
        class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-teal-3 text-n-teal-11"
      >
        <span class="size-5" :class="rule.icon" aria-hidden="true" />
      </span>
      <span class="min-w-0 flex-1">
        <strong class="block truncate text-xs text-n-slate-12">
          {{ modelValue.filename }}
        </strong>
        <span class="text-[0.7rem] text-n-slate-9">
          {{
            t('WHATSAPP_CLOUD_STUDIO.FLOWS.MEDIA.FILE_DETAILS', {
              size: fileSize,
              type: modelValue.content_type,
            })
          }}
        </span>
      </span>
      <button
        type="button"
        class="flex size-10 shrink-0 items-center justify-center rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
        :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.MEDIA.REMOVE_FILE')"
        @click="removeFile"
      >
        <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
      </button>
    </div>

    <div v-if="isUploading" class="space-y-2">
      <progress
        class="h-1.5 w-full overflow-hidden rounded-full accent-n-brand"
        :value="uploadProgress"
        max="100"
      />
      <p class="text-xs text-n-slate-9">
        {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.MEDIA.UPLOADING') }}
      </p>
    </div>

    <label
      v-if="mediaType === 'audio' && hasFile"
      class="flex items-start gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-3"
      :class="!isVoiceCapable && 'opacity-60'"
    >
      <input
        :checked="Boolean(modelValue.is_voice_message)"
        type="checkbox"
        class="reset-base mt-0.5 size-4"
        :disabled="!isVoiceCapable"
        @change="updateConfig({ is_voice_message: $event.target.checked })"
      />
      <span>
        <strong class="block text-xs text-n-slate-12">
          {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.MEDIA.VOICE_NOTE') }}
        </strong>
        <span class="mt-1 block text-[0.7rem] leading-5 text-n-slate-9">
          {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.MEDIA.VOICE_NOTE_HINT') }}
        </span>
      </span>
    </label>

    <label
      v-if="['image', 'video', 'document'].includes(mediaType)"
      class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
    >
      {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.MEDIA.CAPTION') }}
      <textarea
        :value="modelValue.caption || ''"
        rows="3"
        maxlength="1024"
        class="reset-base !mb-0 min-h-20 resize-y rounded-xl border border-n-strong bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
        @input="updateConfig({ caption: $event.target.value })"
      />
    </label>
  </div>
</template>
