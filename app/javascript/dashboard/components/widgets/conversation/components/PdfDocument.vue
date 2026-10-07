<script setup>
import { shallowRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { PDFViewer } from '@embedpdf/vue-pdf-viewer';
import wasmUrl from '@embedpdf/pdfium/pdfium.wasm?url';

const props = defineProps({
  url: { type: String, required: true },
  fileName: { type: String, required: true },
  author: { type: String, default: '' },
});
const emit = defineEmits(['ready']);
const { locale } = useI18n();
const registry = shallowRef(null);

const config = {
  src: props.url,
  wasmUrl: new URL(wasmUrl, window.location.href).href,
  fontFallback: null,
  fonts: { ui: null, signature: null },
  stamp: { defaultLibrary: false, manifests: [] },
  theme: {
    preference: document.body.classList.contains('dark') ? 'dark' : 'light',
  },
  i18n: { defaultLocale: locale.value.replace('_', '-'), fallbackLocale: 'en' },
  tabBar: 'never',
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
  emit('ready');
};

defineExpose({
  setTool: tool =>
    registry.value.getPlugin('annotation').provides().setActiveTool(tool),
  saveCopy: () =>
    registry.value.getPlugin('export').provides().saveAsCopy().toPromise(),
});
</script>

<template>
  <PDFViewer :config="config" class="size-full" @ready="onReady" />
</template>
