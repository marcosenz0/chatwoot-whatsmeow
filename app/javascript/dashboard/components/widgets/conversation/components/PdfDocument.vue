<script setup>
import { onBeforeUnmount, ref, shallowRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { PDFViewer, ZoomMode } from '@embedpdf/vue-pdf-viewer';
import wasmUrl from '@embedpdf/pdfium/pdfium.wasm?url';

const props = defineProps({
  url: { type: String, required: true },
  fileName: { type: String, required: true },
  author: { type: String, default: '' },
});
const emit = defineEmits([
  'ready',
  'pageChange',
  'historyChange',
  'rightPanelChange',
]);
const { locale } = useI18n();
const registry = shallowRef(null);
const viewer = ref(null);
const subscriptions = [];

const sidebars = Object.fromEntries(
  [
    ['sidebar-panel', 'thumbnails-sidebar', 'left'],
    ['annotation-panel', 'annotation-sidebar', 'left'],
    ['signature-panel', 'signature-sidebar', 'left'],
    ['search-panel', 'search-sidebar', 'right'],
    ['comment-panel', 'comment-sidebar', 'right'],
    ['widget-edit-panel', 'widget-edit-sidebar', 'right'],
    ['redaction-panel', 'redaction-sidebar', 'right'],
  ].map(([id, componentId, placement]) => [
    id,
    {
      id,
      position: { placement, slot: 'main' },
      content: { type: 'component', componentId },
      width: '280px',
      collapsible: true,
      defaultOpen: false,
    },
  ])
);
const modals = Object.fromEntries(
  ['print', 'link', 'signature-create'].map(name => [
    `${name}-modal`,
    {
      id: `${name}-modal`,
      content: { type: 'component', componentId: `${name}-modal` },
      maxWidth: '32rem',
      closeOnClickOutside: true,
      closeOnEscape: true,
    },
  ])
);
const selectionMenus = Object.fromEntries(
  [
    [
      'selection',
      [
        'selection:copy',
        'annotation:add-highlight',
        'annotation:add-underline',
        'annotation:add-strikeout',
      ],
    ],
    [
      'annotation',
      [
        'annotation:toggle-comment',
        'annotation:toggle-annotation-style',
        'annotation:delete-selected',
      ],
    ],
    [
      'groupAnnotation',
      ['panel:toggle-annotation-style', 'annotation:delete-all-selected'],
    ],
    ['redaction', ['redaction:delete-selected', 'redaction:commit-selected']],
  ].map(([id, commands]) => [
    id,
    {
      id,
      items: commands.map(commandId => ({
        id: commandId,
        type: 'command-button',
        commandId,
        variant: 'icon',
      })),
    },
  ])
);
const colors = {
  background: {
    app: 'rgb(var(--background-color))',
    surface: 'rgb(var(--background-color))',
    surfaceAlt: 'rgb(var(--slate-3))',
    elevated: 'rgb(var(--background-color))',
    input: 'rgb(var(--slate-3))',
  },
  foreground: {
    primary: 'rgb(var(--slate-12))',
    secondary: 'rgb(var(--slate-11))',
    muted: 'rgb(var(--slate-10))',
  },
  border: {
    default: 'rgb(var(--slate-6))',
    subtle: 'rgb(var(--slate-5))',
  },
};

const config = {
  src: props.url,
  wasmUrl: new URL(wasmUrl, window.location.href).href,
  fontFallback: null,
  fonts: { ui: null, signature: null },
  stamp: { defaultLibrary: false, manifests: [] },
  theme: {
    preference: document.body.classList.contains('dark') ? 'dark' : 'light',
    dark: colors,
    light: colors,
  },
  i18n: { defaultLocale: locale.value.replace('_', '-'), fallbackLocale: 'en' },
  tabBar: 'never',
  ui: {
    schema: {
      id: 'chatwoot-pdf',
      version: '1.0',
      toolbars: {},
      menus: {},
      sidebars,
      modals,
      overlays: {},
      selectionMenus,
    },
  },
  zoom: { defaultZoomLevel: ZoomMode.FitWidth },
  viewport: { viewportGap: 16 },
  disabledCategories: [
    'document-open',
    'document-close',
    'insert-rubber-stamp',
  ],
  annotations: { annotationAuthor: props.author },
  export: { defaultFileName: props.fileName },
};

const onReady = value => {
  registry.value = value;
  const scroll = value.getPlugin('scroll').provides();
  const history = value.getPlugin('history').provides();
  const ui = value.getPlugin('ui').provides();
  subscriptions.push(
    scroll.onLayoutReady(event => {
      emit('pageChange', event);
      if (event.isInitial) {
        const zoom = value.getPlugin('zoom').provides();
        const width = viewer.value.container.clientWidth;
        zoom.requestZoom(
          zoom.getState().currentZoomLevel * (width >= 768 ? 0.7 : 1),
          { vx: width / 2, vy: 0 }
        );
        emit('ready');
      }
    }),
    scroll.onPageChange(event => emit('pageChange', event)),
    history.onHistoryChange(event => emit('historyChange', event.state.global)),
    ui.onSidebarChanged(({ documentId }) =>
      emit(
        'rightPanelChange',
        ui.forDocument(documentId).isSidebarOpen('right', 'main')
      )
    )
  );
};

const commands = () => registry.value.getPlugin('commands').provides();
onBeforeUnmount(() => subscriptions.forEach(unsubscribe => unsubscribe()));

defineExpose({
  setTool: tool =>
    registry.value.getPlugin('annotation').provides().setActiveTool(tool),
  execute: command => commands().execute(command),
  getCommands: ids => ids.map(id => commands().resolve(id)),
  goToPage: pageNumber =>
    registry.value.getPlugin('scroll').provides().scrollToPage({ pageNumber }),
  zoomIn: () => registry.value.getPlugin('zoom').provides().zoomIn(),
  zoomOut: () => registry.value.getPlugin('zoom').provides().zoomOut(),
  saveCopy: () =>
    registry.value.getPlugin('export').provides().saveAsCopy().toPromise(),
});
</script>

<template>
  <PDFViewer ref="viewer" :config="config" class="size-full" @ready="onReady" />
</template>
