<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatBytes } from 'shared/helpers/FileHelper';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  attachments: {
    type: Array,
    default: () => [],
  },
  allowRecordedAudio: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['removeAttachment', 'toggleRecordedAudio']);
const { t } = useI18n();

const visibleAttachments = computed(() =>
  props.attachments
    .map((attachment, index) => ({ attachment, index }))
    .filter(
      ({ attachment }) =>
        !attachment?.isRecordedAudio && !attachment?.isVoiceMessage
    )
);

const onRemoveAttachment = itemIndex => {
  emit(
    'removeAttachment',
    props.attachments.filter((_, index) => index !== itemIndex)
  );
};

const formatFileSize = file => {
  const size = file.byte_size || file.size;
  return formatBytes(size, 0);
};

const isTypeImage = file => {
  const type = file.content_type || file.type;
  return type.includes('image');
};

const AUDIO_FILE_EXTENSION = /\.(aac|amr|m4a|mp3|mpeg|oga|ogg|opus|wav|webm)$/i;

const fileType = file =>
  file?.content_type || file?.type || file?.file?.type || '';

const isTypeAudio = attachment => {
  if (attachment?.isAudio) return true;

  const resource = attachment?.resource || attachment;
  const type = fileType(resource);
  const name = resource?.filename || resource?.name || '';

  return type.startsWith('audio/') || AUDIO_FILE_EXTENSION.test(name);
};

const fileName = file => {
  return file.filename || file.name;
};

const recordedAudioModeLabel = attachment =>
  attachment.sendAsRecordedAudio
    ? t('CONVERSATION.REPLYBOX.RECORDED_AUDIO_LABEL')
    : t('CONVERSATION.REPLYBOX.AUDIO_FILE_LABEL');

const recordedAudioTooltip = attachment =>
  attachment.sendAsRecordedAudio
    ? t('CONVERSATION.REPLYBOX.RECORDED_AUDIO_TOOLTIP')
    : t('CONVERSATION.REPLYBOX.AUDIO_FILE_TOOLTIP');
</script>

<template>
  <div class="flex flex-wrap gap-y-1 gap-x-2 overflow-auto max-h-[12.5rem]">
    <div
      v-for="{ attachment, index } in visibleAttachments"
      :key="attachment.id || attachment.blobSignedId || index"
      class="flex items-center p-1 bg-n-slate-3 gap-1 rounded-md w-[30rem] max-w-full"
    >
      <div class="max-w-[4rem] flex-shrink-0 w-6 flex items-center">
        <img
          v-if="isTypeImage(attachment.resource)"
          class="object-cover w-6 h-6 rounded-sm"
          :src="attachment.thumb"
        />
        <Icon
          v-else-if="isTypeAudio(attachment)"
          icon="i-lucide-audio-lines"
          class="size-5 text-n-slate-10"
        />
        <Icon v-else icon="i-lucide-file" class="size-5 text-n-slate-10" />
      </div>
      <div class="min-w-0 flex-1 overflow-hidden text-ellipsis">
        <span
          class="h-4 overflow-hidden text-sm font-medium text-ellipsis whitespace-nowrap"
        >
          {{ fileName(attachment.resource) }}
        </span>
      </div>
      <div class="shrink-0 justify-center">
        <span class="overflow-hidden text-xs text-ellipsis whitespace-nowrap">
          {{ formatFileSize(attachment.resource) }}
        </span>
      </div>
      <div class="flex items-center justify-center">
        <Button
          v-if="allowRecordedAudio && isTypeAudio(attachment)"
          v-tooltip="recordedAudioTooltip(attachment)"
          :aria-label="recordedAudioTooltip(attachment)"
          :aria-pressed="attachment.sendAsRecordedAudio ? 'true' : 'false'"
          :variant="attachment.sendAsRecordedAudio ? 'solid' : 'outline'"
          :color="attachment.sendAsRecordedAudio ? 'teal' : 'slate'"
          :label="recordedAudioModeLabel(attachment)"
          class="min-w-[5rem] font-semibold shadow-sm"
          xs
          :icon="
            attachment.sendAsRecordedAudio
              ? 'i-lucide-mic'
              : 'i-lucide-file-audio'
          "
          @click="emit('toggleRecordedAudio', index)"
        />
        <Button
          ghost
          slate
          xs
          icon="i-lucide-x"
          @click="onRemoveAttachment(index)"
        />
      </div>
    </div>
  </div>
</template>
