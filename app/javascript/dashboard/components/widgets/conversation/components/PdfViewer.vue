<script setup>
import { computed, nextTick, onMounted, ref, shallowRef } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { attachmentFileName } from 'dashboard/helper/pdfAttachmentHelper';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import MessageAPI from 'dashboard/api/inbox/message';
import EmojiPicker from 'shared/components/emoji/EmojiPicker.vue';
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
  allowMessageActions: { type: Boolean, default: false },
});
const emit = defineEmits(['close', 'forward']);
const show = defineModel('show', { type: Boolean, default: false });
const { t, locale } = useI18n();
const store = useStore();
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
const showReactionPicker = ref(false);
const isSavingStar = ref(false);
const editGroup = ref(null);
const advancedTools = ref([]);
const currentPage = ref(1);
const totalPages = ref(0);
const history = ref({ canUndo: false, canRedo: false });
const rightPanelOpen = ref(false);

const fileName = computed(() => attachmentFileName(props.attachment));
const sender = computed(() => props.attachment.sender || {});
const isStarred = computed(
  () => !!props.attachment.content_attributes?.whatsmeow_starred
);
const title = computed(() =>
  [sender.value.name, fileName.value].filter(Boolean).join(' · ')
);
const conversationId = computed(
  () =>
    props.conversationId ||
    props.attachment.conversation_id ||
    Number(route.params.conversation_id)
);
const readableTime = computed(() =>
  props.attachment.created_at
    ? new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
        dateStyle: 'medium',
        timeStyle: 'short',
      }).format(new Date(props.attachment.created_at * 1000))
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
const tools = computed(() => [
  { id: 'ink', label: t('PDF_VIEWER.DRAW'), icon: 'i-lucide-pencil' },
  {
    id: 'highlight',
    label: t('PDF_VIEWER.HIGHLIGHT'),
    icon: 'i-lucide-highlighter',
  },
  {
    id: 'underline',
    label: t('PDF_VIEWER.UNDERLINE'),
    icon: 'i-lucide-underline',
  },
  {
    id: 'strikeout',
    label: t('PDF_VIEWER.STRIKEOUT'),
    icon: 'i-lucide-strikethrough',
  },
  { id: 'freeText', label: t('PDF_VIEWER.ADD_TEXT'), icon: 'i-lucide-type' },
]);
const toolGroups = computed(() => [
  {
    label: t('PDF_VIEWER.SHAPES'),
    icon: 'i-lucide-shapes',
    commands: [
      'annotation:add-rectangle',
      'annotation:add-circle',
      'annotation:add-line',
      'annotation:add-arrow',
      'annotation:add-polygon',
      'annotation:add-polyline',
    ],
  },
  {
    label: t('PDF_VIEWER.INSERT'),
    icon: 'i-lucide-image-plus',
    commands: ['insert:add-image', 'insert:add-signature'],
  },
  {
    label: t('PDF_VIEWER.FORMS'),
    icon: 'i-lucide-list-checks',
    commands: [
      'form:toggle-fill-mode',
      'form:add-textfield',
      'form:add-checkbox',
      'form:add-radio',
      'form:add-select',
      'form:add-listbox',
    ],
  },
  {
    label: t('PDF_VIEWER.REDACT'),
    icon: 'i-lucide-eraser',
    commands: [
      'redaction:redact-area',
      'redaction:redact-text',
      'redaction:apply-all',
      'redaction:clear-all',
    ],
  },
]);

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
const execute = command => {
  documentRef.value.execute(command);
  showEditMenu.value = false;
  showMoreMenu.value = false;
};
const openToolGroup = group => {
  editGroup.value = group.label;
  advancedTools.value = documentRef.value.getCommands(group.commands);
};
const toggleEditMenu = () => {
  showEditMenu.value = !showEditMenu.value;
  showMoreMenu.value = false;
  editGroup.value = null;
};
const toggleStar = async () => {
  try {
    isSavingStar.value = true;
    const { data } = await MessageAPI.star(
      conversationId.value,
      props.attachment.message_id,
      !isStarred.value
    );
    await store.dispatch('updateMessage', data);
  } catch (error) {
    useAlert(error.response?.data?.message || t('WHATSMEOW_UI.SAVE_ERROR'));
  } finally {
    isSavingStar.value = false;
  }
};
const onReact = async ({ value }) => {
  try {
    await store.dispatch('reactToMessage', {
      conversationId: conversationId.value,
      messageId: props.attachment.message_id,
      emoji: value,
    });
    showReactionPicker.value = false;
  } catch (error) {
    useAlert(error.response?.data?.error || t('CONVERSATION.SEND_FAILED'));
  }
};
const onPageChange = ({ pageNumber, totalPages: count }) => {
  currentPage.value = pageNumber;
  totalPages.value = count;
};
const goToPage = event => {
  const value = Number(event.target.value);
  if (Number.isInteger(value) && value >= 1 && value <= totalPages.value) {
    documentRef.value.goToPage(value);
  } else {
    event.target.value = currentPage.value;
  }
};
const onForward = () => {
  emit('forward', props.attachment);
  onClose();
};

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
          class="z-10 flex h-16 shrink-0 items-center gap-1 border-b border-n-weak bg-n-background px-3 sm:gap-2 sm:px-7 [&>button>span]:size-5"
        >
          <Avatar
            :src="sender.thumbnail || sender.avatar_url"
            :name="sender.name || ''"
            :size="40"
            rounded-full
            class="shrink-0"
          />
          <div class="min-w-0 flex-1">
            <h3
              class="m-0 truncate text-sm font-semibold text-n-slate-12"
              :title="title"
            >
              {{ title }}
            </h3>
            <p class="m-0 truncate text-xs text-n-slate-11">
              {{ readableTime }}
            </p>
          </div>
          <div
            v-on-clickaway="() => (showEditMenu = false)"
            class="relative shrink-0"
          >
            <button
              type="button"
              :aria-label="t('PDF_VIEWER.EDIT')"
              :disabled="!ready"
              :aria-expanded="showEditMenu"
              aria-haspopup="menu"
              class="flex h-10 items-center gap-2 rounded-full border border-n-slate-6 bg-transparent px-4 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40"
              @click="toggleEditMenu"
            >
              <span class="i-lucide-pencil size-4" />
              <span class="hidden sm:inline">{{ t('PDF_VIEWER.EDIT') }}</span>
              <span class="i-lucide-chevron-down size-3" />
            </button>
            <div
              v-if="showEditMenu"
              role="menu"
              class="absolute right-0 top-12 z-50 max-h-[calc(100vh-6rem)] w-64 overflow-y-auto rounded-2xl border border-n-weak bg-n-background p-2 shadow-xl"
            >
              <button
                v-if="editGroup"
                type="button"
                role="menuitem"
                class="mb-1 flex w-full items-center gap-3 border-b border-n-weak px-2 py-2 text-sm font-medium text-n-slate-12"
                @click="
                  editGroup = editGroup === 'advanced' ? null : 'advanced'
                "
              >
                <span class="i-lucide-chevron-left size-4" />{{
                  editGroup === 'advanced' ? t('PDF_VIEWER.EDIT') : editGroup
                }}
              </button>
              <template v-if="!editGroup">
                <button
                  v-for="tool in tools"
                  :key="tool.id"
                  type="button"
                  role="menuitem"
                  class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
                  @click="setTool(tool.id)"
                >
                  <span
                    :class="tool.icon"
                    class="size-4 shrink-0 text-n-slate-11"
                  />{{ tool.label }}
                </button>
                <button
                  type="button"
                  role="menuitem"
                  class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
                  @click="editGroup = 'advanced'"
                >
                  <span
                    class="i-lucide-sliders-horizontal size-4 shrink-0 text-n-slate-11"
                  />{{ t('PDF_VIEWER.MORE_TOOLS') }}
                  <span class="i-lucide-chevron-right ml-auto size-4" />
                </button>
              </template>
              <template v-else-if="editGroup === 'advanced'">
                <button
                  v-for="group in toolGroups"
                  :key="group.label"
                  type="button"
                  role="menuitem"
                  class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2"
                  @click="openToolGroup(group)"
                >
                  <span
                    :class="group.icon"
                    class="size-4 shrink-0 text-n-slate-11"
                  />{{ group.label }}
                  <span class="i-lucide-chevron-right ml-auto size-4" />
                </button>
                <button
                  type="button"
                  role="menuitem"
                  class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2"
                  @click="execute('panel:toggle-annotation-style')"
                >
                  <span class="i-lucide-palette size-4 text-n-slate-11" />{{
                    t('PDF_VIEWER.STYLE')
                  }}
                </button>
                <button
                  type="button"
                  role="menuitem"
                  class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2"
                  @click="setTool(null)"
                >
                  <span
                    class="i-lucide-mouse-pointer-2 size-4 text-n-slate-11"
                  />{{ t('PDF_VIEWER.SELECT') }}
                </button>
                <div class="my-1 border-t border-n-weak" />
                <button
                  type="button"
                  role="menuitem"
                  :disabled="!history.canUndo"
                  class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40"
                  @click="execute('history:undo')"
                >
                  <span class="i-lucide-undo-2 size-4 text-n-slate-11" />{{
                    t('PDF_VIEWER.UNDO')
                  }}
                </button>
                <button
                  type="button"
                  role="menuitem"
                  :disabled="!history.canRedo"
                  class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40"
                  @click="execute('history:redo')"
                >
                  <span class="i-lucide-redo-2 size-4 text-n-slate-11" />{{
                    t('PDF_VIEWER.REDO')
                  }}
                </button>
              </template>
              <template v-else>
                <button
                  v-for="tool in advancedTools"
                  :key="tool.id"
                  type="button"
                  role="menuitem"
                  :disabled="tool.disabled"
                  class="flex w-full rounded-lg px-2 py-2.5 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40"
                  @click="execute(tool.id)"
                >
                  {{ tool.label }}
                </button>
              </template>
            </div>
          </div>
          <Button
            v-tooltip.bottom="t('PDF_VIEWER.SEARCH')"
            :aria-label="t('PDF_VIEWER.SEARCH')"
            :disabled="!ready"
            icon="i-lucide-search"
            slate
            ghost
            @click="execute('panel:toggle-search')"
          />
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
            v-if="allowMessageActions"
            v-tooltip.bottom="
              isStarred ? t('WHATSMEOW_UI.UNSTAR') : t('WHATSMEOW_UI.STAR')
            "
            :aria-label="
              isStarred ? t('WHATSMEOW_UI.UNSTAR') : t('WHATSMEOW_UI.STAR')
            "
            :aria-pressed="isStarred"
            :is-loading="isSavingStar"
            :disabled="isSavingStar"
            :icon="isStarred ? 'i-lucide-star-off' : 'i-lucide-star'"
            slate
            ghost
            @click="toggleStar"
          />
          <div
            v-if="allowMessageActions"
            v-on-clickaway="() => (showReactionPicker = false)"
            class="relative shrink-0"
          >
            <Button
              v-tooltip.bottom="t('GALLERY_VIEW.REACT')"
              :aria-label="t('GALLERY_VIEW.REACT')"
              :aria-expanded="showReactionPicker"
              icon="i-lucide-smile"
              slate
              ghost
              class="[&>span]:size-5"
              @click="showReactionPicker = !showReactionPicker"
            />
            <div
              v-if="showReactionPicker"
              class="absolute right-0 top-12 z-50 rounded-2xl border border-n-weak bg-n-background shadow-xl"
            >
              <EmojiPicker @select="onReact" />
            </div>
          </div>
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
              role="menu"
              class="absolute right-0 top-12 z-50 max-h-[calc(100vh-6rem)] w-64 overflow-y-auto rounded-2xl border border-n-weak bg-n-background p-2 shadow-xl"
            >
              <button
                v-if="conversationId && attachment.message_id"
                type="button"
                role="menuitem"
                class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2"
                @click="goToMessage"
              >
                <span
                  class="i-lucide-message-square size-4 text-n-slate-11"
                />{{ t('GALLERY_VIEW.GO_TO_MESSAGE') }}
              </button>
              <button
                v-if="conversationId && attachment.message_id"
                type="button"
                role="menuitem"
                class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2"
                @click="copyMessageLink"
              >
                <span class="i-lucide-link size-4 text-n-slate-11" />{{
                  t('PDF_VIEWER.COPY_LINK')
                }}
              </button>
              <a
                :href="attachment.data_url"
                target="_blank"
                rel="noopener noreferrer"
                role="menuitem"
                class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2"
              >
                <span class="i-lucide-external-link size-4 text-n-slate-11" />{{
                  t('PDF_VIEWER.OPEN_WITH')
                }}
              </a>
              <button
                type="button"
                role="menuitem"
                class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
                :disabled="!ready || isDownloading"
                @click="saveCopy"
              >
                <span class="i-lucide-save size-4 text-n-slate-11" />{{
                  t('PDF_VIEWER.SAVE_COPY')
                }}
              </button>
              <div class="my-1 border-t border-n-weak" />
              <button
                type="button"
                role="menuitem"
                :disabled="!ready"
                class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
                @click="execute('panel:toggle-sidebar')"
              >
                <span class="i-lucide-panel-left size-4 text-n-slate-11" />{{
                  t('PDF_VIEWER.THUMBNAILS')
                }}
              </button>
              <button
                type="button"
                role="menuitem"
                :disabled="!ready"
                class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
                @click="execute('panel:toggle-comment')"
              >
                <span
                  class="i-lucide-message-square-text size-4 text-n-slate-11"
                />{{ t('PDF_VIEWER.COMMENTS') }}
              </button>
              <button
                type="button"
                role="menuitem"
                :disabled="!ready"
                class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
                @click="execute('zoom:fit-width')"
              >
                <span
                  class="i-lucide-move-horizontal size-4 text-n-slate-11"
                />{{ t('PDF_VIEWER.FIT_WIDTH') }}
              </button>
              <button
                type="button"
                role="menuitem"
                :disabled="!ready"
                class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
                @click="execute('zoom:fit-page')"
              >
                <span class="i-lucide-scan size-4 text-n-slate-11" />{{
                  t('PDF_VIEWER.FIT_PAGE')
                }}
              </button>
              <button
                type="button"
                role="menuitem"
                :disabled="!ready"
                class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-sm text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-50"
                @click="execute('document:print')"
              >
                <span class="i-lucide-printer size-4 text-n-slate-11" />{{
                  t('PDF_VIEWER.PRINT')
                }}
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
            @page-change="onPageChange"
            @history-change="history = $event"
            @right-panel-change="rightPanelOpen = $event"
          />
          <nav
            v-if="ready"
            :aria-label="t('PDF_VIEWER.NAVIGATION')"
            class="absolute bottom-4 z-10 flex w-14 flex-col items-center gap-2 rounded-2xl border border-n-slate-6 bg-n-background p-1.5 text-n-slate-12 shadow-sm [&>button>span]:size-5"
            :class="rightPanelOpen ? 'right-[18.5rem]' : 'right-4'"
          >
            <input
              :value="currentPage"
              :aria-label="t('PDF_VIEWER.PAGE')"
              inputmode="numeric"
              type="text"
              class="reset-base h-10 w-10 rounded-xl border border-n-slate-6 bg-transparent p-0 text-center text-sm text-n-slate-12 focus:border-n-slate-8 focus:outline-none"
              @change="goToPage"
              @keydown.enter="goToPage"
            />
            <span class="py-1 text-sm tabular-nums">{{ totalPages }}</span>
            <div class="my-1 w-8 border-t border-n-weak" />
            <Button
              :aria-label="t('PDF_VIEWER.PREVIOUS_PAGE')"
              :disabled="currentPage === 1"
              icon="i-lucide-chevron-up"
              slate
              ghost
              class="size-10"
              @click="documentRef.goToPage(currentPage - 1)"
            />
            <Button
              :aria-label="t('PDF_VIEWER.NEXT_PAGE')"
              :disabled="currentPage === totalPages"
              icon="i-lucide-chevron-down"
              slate
              ghost
              class="size-10"
              @click="documentRef.goToPage(currentPage + 1)"
            />
            <div class="my-1 w-8 border-t border-n-weak" />
            <Button
              :aria-label="t('PDF_VIEWER.ZOOM_IN')"
              icon="i-lucide-zoom-in"
              slate
              ghost
              class="size-10"
              @click="documentRef.zoomIn()"
            />
            <Button
              :aria-label="t('PDF_VIEWER.ZOOM_OUT')"
              icon="i-lucide-zoom-out"
              slate
              ghost
              class="size-10"
              @click="documentRef.zoomOut()"
            />
          </nav>
        </main>
      </div>
    </woot-modal>
  </TeleportWithDirection>
</template>
