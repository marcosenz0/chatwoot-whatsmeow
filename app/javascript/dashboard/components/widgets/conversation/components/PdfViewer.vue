<script setup>
import { computed, nextTick, onMounted, ref, shallowRef } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { attachmentFileName } from 'dashboard/helper/pdfAttachmentHelper';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { downloadFile } from '@chatwoot/utils';
import Button from 'next/button/Button.vue';
import Avatar from 'next/avatar/Avatar.vue';
import Spinner from 'next/spinner/Spinner.vue';
import TeleportWithDirection from 'next/TeleportWithDirection.vue';

const props = defineProps({
  attachment: { type: Object, required: true },
  conversationId: { type: Number, default: null },
  allowForward: { type: Boolean, default: false },
});
const emit = defineEmits(['close', 'forward']);
const show = defineModel('show', { type: Boolean, default: false });
const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const currentUser = useMapGetter('getCurrentUser');
const pdfDocument = shallowRef(null);
const documentRef = ref(null);
const ready = ref(false);
const loadError = ref(false);
const isDownloading = ref(false);
const showEditMenu = ref(false);
const showMoreMenu = ref(false);

const fileName = computed(() => attachmentFileName(props.attachment));
const sender = computed(() => props.attachment.sender || {});
const conversationId = computed(
  () => props.conversationId || Number(route.params.conversation_id)
);
const readableTime = computed(() =>
  props.attachment.created_at
    ? messageTimestamp(props.attachment.created_at, 'LLL d yyyy, h:mm a')
    : ''
);
const messageLocation = computed(() => ({
  path: frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: conversationId.value,
    })
  ),
  query: { messageId: String(props.attachment.message_id) },
}));
const messageUrl = computed(
  () =>
    new URL(router.resolve(messageLocation.value).href, window.location.origin)
      .href
);
const tools = [
  { id: 'ink', label: 'PDF_VIEWER.DRAW', icon: 'i-lucide-pencil' },
  {
    id: 'highlight',
    label: 'PDF_VIEWER.HIGHLIGHT',
    icon: 'i-lucide-highlighter',
  },
  {
    id: 'underline',
    label: 'PDF_VIEWER.UNDERLINE',
    icon: 'i-lucide-underline',
  },
  {
    id: 'strikeout',
    label: 'PDF_VIEWER.STRIKEOUT',
    icon: 'i-lucide-strikethrough',
  },
  { id: 'freeText', label: 'PDF_VIEWER.ADD_TEXT', icon: 'i-lucide-type' },
];

const onClose = () => emit('close');
const goToMessage = async () => {
  onClose();
  await router.push(messageLocation.value);
  await nextTick();
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: props.attachment.message_id,
    conversationId: conversationId.value,
  });
};
const copyMessageLink = async () => {
  try {
    await navigator.clipboard.writeText(messageUrl.value);
    useAlert(t('PDF_VIEWER.LINK_COPIED'));
    showMoreMenu.value = false;
  } catch (error) {
    useAlert(t('PDF_VIEWER.COPY_ERROR'));
  }
};
const onDownload = async () => {
  try {
    isDownloading.value = true;
    await downloadFile({
      url: props.attachment.data_url,
      type: 'file',
      extension: 'pdf',
    });
  } catch (error) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  } finally {
    isDownloading.value = false;
  }
};
const saveCopy = async () => {
  try {
    isDownloading.value = true;
    const buffer = await documentRef.value.saveCopy();
    const url = URL.createObjectURL(
      new Blob([buffer], { type: 'application/pdf' })
    );
    const link = Object.assign(document.createElement('a'), {
      href: url,
      download: fileName.value,
    });
    link.click();
    URL.revokeObjectURL(url);
    showMoreMenu.value = false;
  } catch (error) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  } finally {
    isDownloading.value = false;
  }
};
const setTool = tool => {
  documentRef.value.setTool(tool);
  showEditMenu.value = false;
};
const onForward = () => {
  emit('forward', props.attachment);
  onClose();
};

useKeyboardEvents({ Escape: { action: onClose } });
onMounted(async () => {
  try {
    pdfDocument.value = (await import('./PdfDocument.vue')).default;
  } catch (error) {
    loadError.value = true;
  }
});
</script>

<template>
  <TeleportWithDirection to="body">
    <woot-modal
      v-model:show="show"
      full-width
      :show-close-button="false"
      @close="onClose"
    >
      <div
        class="flex size-full flex-col overflow-hidden bg-n-background"
        @click.stop
      >
        <header
          class="flex shrink-0 items-center gap-3 border-b border-n-weak px-4 py-3"
        >
          <Avatar
            v-if="sender.thumbnail || sender.avatar_url"
            :src="sender.thumbnail || sender.avatar_url"
            :name="sender.name || ''"
            :size="40"
            rounded-full
          />
          <div class="min-w-0 flex-1">
            <h3
              class="m-0 truncate text-sm font-semibold text-n-slate-12"
              :title="fileName"
            >
              {{ fileName }}
            </h3>
            <p class="m-0 truncate text-xs text-n-slate-11">
              {{ [sender.name, readableTime].filter(Boolean).join(' · ') }}
            </p>
          </div>
          <div v-on-clickaway="() => (showEditMenu = false)" class="relative">
            <Button
              :label="t('PDF_VIEWER.EDIT')"
              :disabled="!ready"
              icon="i-lucide-pencil"
              slate
              faded
              @click="showEditMenu = !showEditMenu"
            />
            <div
              v-if="showEditMenu"
              class="absolute right-0 top-12 z-50 w-52 rounded-lg border border-n-weak bg-n-background p-1 shadow-xl"
            >
              <button
                v-for="tool in tools"
                :key="tool.id"
                type="button"
                class="flex w-full items-center gap-2 rounded px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2"
                @click="setTool(tool.id)"
              >
                <span :class="tool.icon" class="size-4" />{{ t(tool.label) }}
              </button>
              <button
                type="button"
                class="flex w-full items-center gap-2 rounded px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2"
                @click="setTool(null)"
              >
                <span class="i-lucide-mouse-pointer-2 size-4" />{{
                  t('PDF_VIEWER.SELECT')
                }}
              </button>
            </div>
          </div>
          <Button
            v-if="conversationId && attachment.message_id"
            v-tooltip.bottom="t('GALLERY_VIEW.GO_TO_MESSAGE')"
            :aria-label="t('GALLERY_VIEW.GO_TO_MESSAGE')"
            icon="i-lucide-message-square"
            slate
            ghost
            @click="goToMessage"
          />
          <Button
            v-if="allowForward"
            v-tooltip.bottom="t('GALLERY_VIEW.FORWARD')"
            :aria-label="t('GALLERY_VIEW.FORWARD')"
            icon="i-lucide-forward"
            slate
            ghost
            @click="onForward"
          />
          <Button
            v-tooltip.bottom="t('CONVERSATION.DOWNLOAD')"
            :aria-label="t('CONVERSATION.DOWNLOAD')"
            :is-loading="isDownloading"
            :disabled="isDownloading"
            icon="i-lucide-download"
            slate
            ghost
            @click="onDownload"
          />
          <div v-on-clickaway="() => (showMoreMenu = false)" class="relative">
            <Button
              :aria-label="t('GALLERY_VIEW.MORE')"
              icon="i-lucide-ellipsis-vertical"
              slate
              ghost
              @click="showMoreMenu = !showMoreMenu"
            />
            <div
              v-if="showMoreMenu"
              class="absolute right-0 top-12 z-50 w-60 rounded-lg border border-n-weak bg-n-background p-1 shadow-xl"
            >
              <button
                v-if="conversationId && attachment.message_id"
                type="button"
                class="flex w-full rounded px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2"
                @click="goToMessage"
              >
                {{ t('GALLERY_VIEW.GO_TO_MESSAGE') }}
              </button>
              <button
                v-if="conversationId && attachment.message_id"
                type="button"
                class="flex w-full rounded px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2"
                @click="copyMessageLink"
              >
                {{ t('PDF_VIEWER.COPY_LINK') }}
              </button>
              <a
                :href="attachment.data_url"
                target="_blank"
                rel="noopener noreferrer"
                class="flex w-full rounded px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2"
              >
                {{ t('PDF_VIEWER.OPEN_WITH') }}
              </a>
              <button
                type="button"
                class="flex w-full rounded px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
                :disabled="!ready || isDownloading"
                @click="saveCopy"
              >
                {{ t('PDF_VIEWER.SAVE_COPY') }}
              </button>
            </div>
          </div>
          <Button
            :aria-label="t('GALLERY_VIEW.CLOSE')"
            icon="i-lucide-x"
            slate
            ghost
            @click="onClose"
          />
        </header>
        <main class="relative min-h-0 flex-1">
          <p
            v-if="loadError"
            role="alert"
            class="m-0 p-6 text-center text-n-ruby-11"
          >
            {{ t('PDF_VIEWER.LOAD_ERROR') }}
          </p>
          <div
            v-else-if="!pdfDocument"
            role="status"
            class="flex size-full items-center justify-center gap-3 text-n-slate-11"
          >
            <Spinner />{{ t('PDF_VIEWER.LOADING') }}
          </div>
          <component
            :is="pdfDocument"
            v-else
            ref="documentRef"
            :url="attachment.data_url"
            :file-name="fileName"
            :author="currentUser?.name || ''"
            @ready="ready = true"
          />
        </main>
      </div>
    </woot-modal>
  </TeleportWithDirection>
</template>
