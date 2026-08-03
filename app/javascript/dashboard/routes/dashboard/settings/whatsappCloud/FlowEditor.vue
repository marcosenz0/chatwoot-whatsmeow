<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  toRaw,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import StudioSelect from './StudioSelect.vue';
import StudioTemplateParameterFields from './StudioTemplateParameterFields.vue';
import {
  hydrateStudioTemplateParameters,
  isStudioTemplateSupported,
  templateParametersComplete,
  templateQuickReplies,
} from './templateParameterUtils';

const props = defineProps({
  flow: { type: Object, required: true },
  templates: { type: Array, default: () => [] },
  isSaving: { type: Boolean, default: false },
  isPublishing: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'save', 'publish']);
const { t } = useI18n();

const cloneFlow = flow => JSON.parse(JSON.stringify(toRaw(flow)));
const draft = reactive(cloneFlow(props.flow));
const savedDraftSnapshot = ref(JSON.stringify(cloneFlow(props.flow)));
const selectedNodeId = ref(
  draft.definition.nodes.find(node => node.type === 'trigger')?.id || null
);
const selectedNodeIds = ref(selectedNodeId.value ? [selectedNodeId.value] : []);
const pendingConnection = ref(null);
const interaction = ref(null);
const selectionBox = ref(null);
const selectedEdgeId = ref(null);
const canvasRef = ref(null);
const svgRef = ref(null);
const discardDialogRef = ref(null);
const viewport = reactive({ x: 56, y: 56, zoom: 1 });

const MIN_ZOOM = 0.35;
const MAX_ZOOM = 1.8;
const NODE_WIDTH = 260;

const nodeTypes = [
  { type: 'message', icon: 'i-lucide-message-square-text' },
  { type: 'wait', icon: 'i-lucide-timer' },
  { type: 'condition', icon: 'i-lucide-git-branch' },
  { type: 'action', icon: 'i-lucide-zap' },
  { type: 'end', icon: 'i-lucide-circle-stop' },
];

const selectedNode = computed(() =>
  draft.definition.nodes.find(node => node.id === selectedNodeId.value)
);

const selectedNodes = computed(() =>
  draft.definition.nodes.filter(node => selectedNodeIds.value.includes(node.id))
);

const hasMultipleSelectedNodes = computed(
  () => selectedNodeIds.value.length > 1
);

const selectedEdge = computed(() =>
  draft.definition.edges.find(edge => edge.id === selectedEdgeId.value)
);

const viewportTransform = computed(
  () => `translate(${viewport.x} ${viewport.y}) scale(${viewport.zoom})`
);

const nodeTransform = node =>
  `translate(${node.position.x} ${node.position.y})`;

const selectionBoxGeometry = computed(() => {
  if (!selectionBox.value) return null;
  const { start, current } = selectionBox.value;
  return {
    x: Math.min(start.x, current.x),
    y: Math.min(start.y, current.y),
    width: Math.abs(current.x - start.x),
    height: Math.abs(current.y - start.y),
  };
});

const zoomPercentage = computed(() => `${Math.round(viewport.zoom * 100)}%`);

const approvedTemplates = computed(() =>
  props.templates.filter(
    template => template.status?.toLowerCase() === 'approved'
  )
);

const configuredTemplate = computed(() =>
  approvedTemplates.value.find(
    template =>
      template.name === selectedNode.value?.config?.template_name &&
      template.language === selectedNode.value?.config?.language
  )
);

const selectedTemplate = computed(() =>
  isStudioTemplateSupported(configuredTemplate.value)
    ? configuredTemplate.value
    : null
);

const selectedTemplateKey = computed(() => {
  if (!selectedNode.value?.config?.template_name) return '';
  return `${selectedNode.value.config.template_name}|${selectedNode.value.config.language}`;
});

const selectedTemplateUnsupported = computed(
  () =>
    selectedNode.value?.config?.mode === 'template' &&
    selectedNode.value?.config?.template_name &&
    !isStudioTemplateSupported(configuredTemplate.value)
);

watch(
  [selectedNode, selectedTemplate],
  ([node, template]) => {
    if (!node || node.config?.mode !== 'template' || !template) return;
    node.config.processed_params = hydrateStudioTemplateParameters(
      template,
      node.config.processed_params,
      { quickReplies: node.config.buttons || [] }
    );
  },
  { immediate: true }
);

const flowHasUnsupportedTemplates = computed(() =>
  draft.definition.nodes.some(node => {
    if (node.type !== 'message' || node.config?.mode !== 'template') {
      return false;
    }
    const template = approvedTemplates.value.find(
      record =>
        record.name === node.config.template_name &&
        record.language === node.config.language
    );
    return node.config.template_name && !isStudioTemplateSupported(template);
  })
);

const templateParametersForNode = (node, template) =>
  hydrateStudioTemplateParameters(template, node.config?.processed_params, {
    quickReplies: node.config?.buttons || [],
  });

const flowHasIncompleteTemplateParameters = computed(() =>
  draft.definition.nodes.some(node => {
    if (node.type !== 'message' || node.config?.mode !== 'template') {
      return false;
    }
    const template = approvedTemplates.value.find(
      record =>
        record.name === node.config.template_name &&
        record.language === node.config.language
    );
    return (
      isStudioTemplateSupported(template) &&
      !templateParametersComplete(templateParametersForNode(node, template))
    );
  })
);

const selectedTemplateParametersIncomplete = computed(
  () =>
    selectedNode.value?.config?.mode === 'template' &&
    selectedTemplate.value &&
    !templateParametersComplete(
      templateParametersForNode(selectedNode.value, selectedTemplate.value)
    )
);

const hasUnsavedChanges = computed(
  () => JSON.stringify(toRaw(draft)) !== savedDraftSnapshot.value
);

watch(
  () => props.flow,
  flow => {
    const clonedFlow = cloneFlow(flow);
    Object.assign(draft, clonedFlow);
    savedDraftSnapshot.value = JSON.stringify(clonedFlow);
    selectedNodeId.value =
      clonedFlow.definition.nodes.find(node => node.type === 'trigger')?.id ||
      null;
    selectedNodeIds.value = selectedNodeId.value ? [selectedNodeId.value] : [];
  }
);

const nodeHeight = node => {
  if (node.type === 'message') {
    return Math.max(150, 122 + (node.config?.buttons?.length || 0) * 30);
  }
  return 126;
};

const nodeTypeLabel = type => {
  const labels = {
    trigger: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.TRIGGER'),
    message: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.MESSAGE'),
    wait: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.WAIT'),
    condition: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.CONDITION'),
    action: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.ACTION'),
    end: t('WHATSAPP_CLOUD_STUDIO.FLOWS.NODE_TYPES.END'),
  };
  return labels[type];
};

const flowStatusLabel = status => {
  const labels = {
    draft: t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.DRAFT'),
    active: t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.ACTIVE'),
    paused: t('WHATSAPP_CLOUD_STUDIO.FLOWS.STATUS.PAUSED'),
  };
  return labels[status];
};

const actionLabel = action => {
  const labels = {
    add_label: t('WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.ADD_LABEL'),
    remove_label: t('WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.REMOVE_LABEL'),
    open_conversation: t(
      'WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.OPEN_CONVERSATION'
    ),
    resolve_conversation: t(
      'WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.RESOLVE_CONVERSATION'
    ),
  };
  return labels[action];
};

const conditionFieldLabel = field => {
  const labels = {
    last_button_id: t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.LAST_BUTTON'),
    name: t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTACT_NAME'),
    email: t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTACT_EMAIL'),
    phone_number: t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTACT_PHONE'),
  };
  return labels[field] || field;
};

const conditionOperatorLabel = operator => {
  const labels = {
    equals: t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.EQUALS'),
    not_equals: t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.NOT_EQUALS'),
    contains: t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTAINS'),
    present: t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.PRESENT'),
  };
  return labels[operator] || operator;
};

const conditionHandleLabel = handle =>
  handle === 'true'
    ? t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TRUE_HANDLE')
    : t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.FALSE_HANDLE');

const templateOptionLabel = template =>
  `${template.name} - ${template.language}`;

const selectableTemplateLabel = template => {
  const label = templateOptionLabel(template);
  return isStudioTemplateSupported(template)
    ? label
    : `${label} - ${t(
        'WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.UNSUPPORTED_OPTION'
      )}`;
};

const nodeTitle = node => nodeTypeLabel(node.type);

const nodeSubtitle = node => {
  if (node.type === 'trigger') {
    return draft.trigger_type === 'keyword'
      ? draft.trigger_config.keywords?.join(', ')
      : t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.ANY_MESSAGE');
  }
  if (node.type === 'message') {
    return node.config.mode === 'template'
      ? node.config.template_name ||
          t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SELECT_TEMPLATE')
      : node.config.text ||
          t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.EMPTY_MESSAGE');
  }
  if (node.type === 'wait') {
    return t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.WAIT_MINUTES', {
      count: node.config.duration || 1,
    });
  }
  if (node.type === 'condition') {
    return node.config.field
      ? `${conditionFieldLabel(node.config.field)} - ${conditionOperatorLabel(
          node.config.operator
        )}`
      : t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONFIGURE_CONDITION');
  }
  if (node.type === 'action') {
    return node.config.action
      ? actionLabel(node.config.action)
      : t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONFIGURE_ACTION');
  }
  return t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.END_DESCRIPTION');
};

const nodeIcon = node => {
  if (node.type === 'trigger') return 'i-lucide-play';
  return nodeTypes.find(item => item.type === node.type)?.icon;
};

const nodeTone = node => {
  const tones = {
    trigger: 'bg-n-teal-3 text-n-teal-11',
    message: 'bg-n-blue-3 text-n-blue-11',
    wait: 'bg-n-amber-3 text-n-amber-11',
    condition: 'bg-n-iris-3 text-n-iris-11',
    action: 'bg-n-ruby-3 text-n-ruby-11',
    end: 'bg-n-slate-3 text-n-slate-11',
  };
  return tones[node.type];
};

const handleY = (node, handle = 'default') => {
  if (handle === 'default') return node.position.y + 58;
  if (handle === 'true') return node.position.y + 82;
  if (handle === 'false') return node.position.y + 108;
  const buttonIndex = node.config?.buttons?.findIndex(
    button => button.id === handle
  );
  return node.position.y + 122 + Math.max(0, buttonIndex) * 30;
};

const edgeGeometry = edge => {
  const source = draft.definition.nodes.find(node => node.id === edge.source);
  const target = draft.definition.nodes.find(node => node.id === edge.target);
  if (!source || !target) return null;
  const sourceX = source.position.x + NODE_WIDTH;
  const sourceY = handleY(source, edge.source_handle || 'default');
  const targetX = target.position.x;
  const targetY = target.position.y + 58;
  const controlOffset = Math.max(80, Math.abs(targetX - sourceX) / 2);
  return {
    sourceX,
    sourceY,
    targetX,
    targetY,
    firstControlX: sourceX + controlOffset,
    secondControlX: targetX - controlOffset,
  };
};

const geometryPath = geometry => {
  if (!geometry) return '';
  return `M ${geometry.sourceX} ${geometry.sourceY} C ${geometry.firstControlX} ${geometry.sourceY}, ${geometry.secondControlX} ${geometry.targetY}, ${geometry.targetX} ${geometry.targetY}`;
};

const edgePath = edge => geometryPath(edgeGeometry(edge));

const edgeMidpoint = edge => {
  const geometry = edgeGeometry(edge);
  if (!geometry) return { x: 0, y: 0 };
  return {
    x:
      (geometry.sourceX +
        3 * geometry.firstControlX +
        3 * geometry.secondControlX +
        geometry.targetX) /
      8,
    y:
      (geometry.sourceY +
        3 * geometry.sourceY +
        3 * geometry.targetY +
        geometry.targetY) /
      8,
  };
};

const pendingConnectionPath = computed(() => {
  if (!pendingConnection.value?.point) return '';
  const source = draft.definition.nodes.find(
    node => node.id === pendingConnection.value.source
  );
  if (!source) return '';
  const sourceX = source.position.x + NODE_WIDTH;
  const sourceY = handleY(
    source,
    pendingConnection.value.sourceHandle || 'default'
  );
  const targetX = pendingConnection.value.point.x;
  const targetY = pendingConnection.value.point.y;
  const controlOffset = Math.max(80, Math.abs(targetX - sourceX) / 2);
  return geometryPath({
    sourceX,
    sourceY,
    targetX,
    targetY,
    firstControlX: sourceX + controlOffset,
    secondControlX: targetX - controlOffset,
  });
});

const createId = prefix =>
  `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

const defaultConfig = type => {
  if (type === 'message') {
    return { mode: 'session', text: '', buttons: [], processed_params: {} };
  }
  if (type === 'wait') return { duration: 5 };
  if (type === 'condition') {
    return { field: 'last_button_id', operator: 'equals', value: '' };
  }
  if (type === 'action') return { action: 'add_label', value: '' };
  return {};
};

const addNode = type => {
  const count = draft.definition.nodes.length;
  const node = {
    id: createId(type),
    type,
    position: {
      x: 360 + (count % 3) * 300,
      y: 120 + Math.floor(count / 3) * 190,
    },
    config: defaultConfig(type),
  };
  draft.definition.nodes.push(node);
  selectedNodeId.value = node.id;
  selectedNodeIds.value = [node.id];
};

const clearSelection = () => {
  selectedNodeId.value = null;
  selectedNodeIds.value = [];
  selectedEdgeId.value = null;
  pendingConnection.value = null;
};

const selectNode = (nodeId, event = {}) => {
  const shouldToggle = event.ctrlKey || event.metaKey || event.shiftKey;
  if (shouldToggle) {
    selectedNodeIds.value = selectedNodeIds.value.includes(nodeId)
      ? selectedNodeIds.value.filter(id => id !== nodeId)
      : [...selectedNodeIds.value, nodeId];
  } else if (!selectedNodeIds.value.includes(nodeId)) {
    selectedNodeIds.value = [nodeId];
  }
  selectedNodeId.value = selectedNodeIds.value.includes(nodeId)
    ? nodeId
    : selectedNodeIds.value.at(-1) || null;
  selectedEdgeId.value = null;
};

const handleNodeClick = (event, nodeId) => {
  if (event.detail === 0) selectNode(nodeId, event);
};

const deleteSelectedNodes = () => {
  const removableIds = selectedNodeIds.value.filter(id => {
    const node = draft.definition.nodes.find(item => item.id === id);
    return node && node.type !== 'trigger';
  });
  if (!removableIds.length) return;
  draft.definition.nodes = draft.definition.nodes.filter(
    node => !removableIds.includes(node.id)
  );
  draft.definition.edges = draft.definition.edges.filter(
    edge =>
      !removableIds.includes(edge.source) && !removableIds.includes(edge.target)
  );
  const remainingSelection = selectedNodeIds.value.filter(
    id => !removableIds.includes(id)
  );
  selectedNodeIds.value = remainingSelection;
  selectedNodeId.value = remainingSelection.at(-1) || null;
  selectedEdgeId.value = null;
};

const deleteSelectedNode = () => {
  if (!selectedNode.value || selectedNode.value.type === 'trigger') return;
  const id = selectedNode.value.id;
  draft.definition.nodes = draft.definition.nodes.filter(
    node => node.id !== id
  );
  draft.definition.edges = draft.definition.edges.filter(
    edge => edge.source !== id && edge.target !== id
  );
  selectedEdgeId.value = null;
  selectedNodeIds.value = selectedNodeIds.value.filter(nodeId => nodeId !== id);
  selectedNodeId.value = selectedNodeIds.value.at(-1) || null;
};

const duplicateSelectedNode = () => {
  if (!selectedNode.value || selectedNode.value.type === 'trigger') return;
  const duplicatedNode = cloneFlow(selectedNode.value);
  duplicatedNode.id = createId(selectedNode.value.type);
  duplicatedNode.position = {
    x: selectedNode.value.position.x + 56,
    y: selectedNode.value.position.y + 56,
  };
  draft.definition.nodes.push(duplicatedNode);
  selectedNodeId.value = duplicatedNode.id;
  selectedNodeIds.value = [duplicatedNode.id];
  selectedEdgeId.value = null;
};

const sourcePoint = (nodeId, sourceHandle = 'default') => {
  const node = draft.definition.nodes.find(item => item.id === nodeId);
  return node
    ? {
        x: node.position.x + NODE_WIDTH + 100,
        y: handleY(node, sourceHandle),
      }
    : null;
};

const startConnection = (nodeId, sourceHandle = 'default') => {
  pendingConnection.value = {
    source: nodeId,
    sourceHandle,
    point: sourcePoint(nodeId, sourceHandle),
  };
  selectedEdgeId.value = null;
};

const finishConnection = targetId => {
  if (!pendingConnection.value || pendingConnection.value.source === targetId) {
    pendingConnection.value = null;
    return;
  }
  const { source, sourceHandle } = pendingConnection.value;
  draft.definition.edges = draft.definition.edges.filter(
    edge =>
      !(
        edge.source === source &&
        (edge.source_handle || 'default') === sourceHandle
      )
  );
  draft.definition.edges.push({
    id: createId('edge'),
    source,
    target: targetId,
    source_handle: sourceHandle,
  });
  selectedEdgeId.value = null;
  pendingConnection.value = null;
};

const removeOutgoingEdge = (sourceId, sourceHandle = 'default') => {
  draft.definition.edges = draft.definition.edges.filter(
    edge =>
      !(
        edge.source === sourceId &&
        (edge.source_handle || 'default') === sourceHandle
      )
  );
};

const removeEdge = edgeId => {
  draft.definition.edges = draft.definition.edges.filter(
    edge => edge.id !== edgeId
  );
  selectedEdgeId.value = null;
};

const selectEdge = edgeId => {
  selectedEdgeId.value = edgeId;
  selectedNodeId.value = null;
  selectedNodeIds.value = [];
  pendingConnection.value = null;
};

const canvasPoint = event => {
  const bounds = svgRef.value.getBoundingClientRect();
  return {
    x: (event.clientX - bounds.left - viewport.x) / viewport.zoom,
    y: (event.clientY - bounds.top - viewport.y) / viewport.zoom,
  };
};

function moveInteraction(event) {
  if (!interaction.value) return;

  if (interaction.value.type === 'node') {
    const point = canvasPoint(event);
    const deltaX = point.x - interaction.value.pointer.x;
    const deltaY = point.y - interaction.value.pointer.y;
    draft.definition.nodes.forEach(node => {
      const initialPosition = interaction.value.positions[node.id];
      if (!initialPosition) return;
      node.position.x = initialPosition.x + deltaX;
      node.position.y = initialPosition.y + deltaY;
    });
  }

  if (interaction.value.type === 'pan') {
    viewport.x =
      interaction.value.startX + event.clientX - interaction.value.pointerX;
    viewport.y =
      interaction.value.startY + event.clientY - interaction.value.pointerY;
  }

  if (interaction.value.type === 'connection' && pendingConnection.value) {
    pendingConnection.value.point = canvasPoint(event);
  }

  if (interaction.value.type === 'selection') {
    selectionBox.value.current = canvasPoint(event);
  }
}

function stopInteraction(event) {
  if (interaction.value?.type === 'connection' && pendingConnection.value) {
    const target = document
      .elementFromPoint(event.clientX, event.clientY)
      ?.closest('[data-flow-target]');
    if (target?.dataset.flowTarget) {
      finishConnection(target.dataset.flowTarget);
    } else {
      pendingConnection.value = null;
    }
  }

  if (interaction.value?.type === 'selection' && selectionBox.value) {
    const { start, current } = selectionBox.value;
    const left = Math.min(start.x, current.x);
    const right = Math.max(start.x, current.x);
    const top = Math.min(start.y, current.y);
    const bottom = Math.max(start.y, current.y);
    const selectedIds = draft.definition.nodes
      .filter(node => {
        const nodeRight = node.position.x + NODE_WIDTH;
        const nodeBottom = node.position.y + nodeHeight(node);
        return (
          node.position.x <= right &&
          nodeRight >= left &&
          node.position.y <= bottom &&
          nodeBottom >= top
        );
      })
      .map(node => node.id);
    selectedNodeIds.value = selectedIds;
    selectedNodeId.value = selectedIds.at(-1) || null;
    selectedEdgeId.value = null;
    selectionBox.value = null;
  }

  interaction.value = null;
  window.removeEventListener('pointermove', moveInteraction);
  window.removeEventListener('pointerup', stopInteraction);
  window.removeEventListener('pointercancel', stopInteraction);
}

const addInteractionListeners = () => {
  window.addEventListener('pointermove', moveInteraction);
  window.addEventListener('pointerup', stopInteraction, { once: true });
  window.addEventListener('pointercancel', stopInteraction, { once: true });
};

const startNodeDrag = (event, node) => {
  if (event.button !== 0) return;
  event.preventDefault();
  selectNode(node.id, event);
  const draggingNodeIds = selectedNodeIds.value.includes(node.id)
    ? selectedNodeIds.value
    : [node.id];
  interaction.value = {
    type: 'node',
    pointer: canvasPoint(event),
    positions: Object.fromEntries(
      draft.definition.nodes
        .filter(item => draggingNodeIds.includes(item.id))
        .map(item => [item.id, { ...item.position }])
    ),
  };
  addInteractionListeners();
};

const startCanvasPan = event => {
  const backgroundClicked =
    event.target === svgRef.value ||
    event.target?.dataset?.flowCanvasBackground === 'true';
  if (![0, 1, 2].includes(event.button) || !backgroundClicked) return;
  event.preventDefault();
  if (event.button === 2) {
    const point = canvasPoint(event);
    interaction.value = { type: 'selection' };
    selectionBox.value = { start: point, current: point };
    selectedEdgeId.value = null;
    addInteractionListeners();
    return;
  }
  if (event.button === 0) clearSelection();
  interaction.value = {
    type: 'pan',
    pointerX: event.clientX,
    pointerY: event.clientY,
    startX: viewport.x,
    startY: viewport.y,
  };
  selectedEdgeId.value = null;
  addInteractionListeners();
};

const startConnectionDrag = (event, nodeId, sourceHandle = 'default') => {
  if (event.button !== 0) return;
  event.preventDefault();
  startConnection(nodeId, sourceHandle);
  pendingConnection.value.point = canvasPoint(event);
  interaction.value = { type: 'connection' };
  addInteractionListeners();
};

const setZoom = (nextZoom, focus = null) => {
  const bounds = svgRef.value?.getBoundingClientRect();
  if (!bounds) return;
  const zoom = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, nextZoom));
  const focusPoint = focus || {
    x: bounds.left + bounds.width / 2,
    y: bounds.top + bounds.height / 2,
  };
  const worldX = (focusPoint.x - bounds.left - viewport.x) / viewport.zoom;
  const worldY = (focusPoint.y - bounds.top - viewport.y) / viewport.zoom;
  viewport.x = focusPoint.x - bounds.left - worldX * zoom;
  viewport.y = focusPoint.y - bounds.top - worldY * zoom;
  viewport.zoom = zoom;
};

const zoomIn = () => setZoom(viewport.zoom + 0.15);
const zoomOut = () => setZoom(viewport.zoom - 0.15);

const handleCanvasWheel = event => {
  if (event.ctrlKey || event.metaKey) {
    const factor = event.deltaY > 0 ? 0.9 : 1.1;
    setZoom(viewport.zoom * factor, { x: event.clientX, y: event.clientY });
    return;
  }
  viewport.x -= event.deltaX;
  viewport.y -= event.deltaY;
};

const fitView = () => {
  const bounds = canvasRef.value?.getBoundingClientRect();
  const nodes = draft.definition.nodes;
  if (!bounds?.width || !bounds?.height || !nodes.length) return;
  const minX = Math.min(...nodes.map(node => node.position.x));
  const minY = Math.min(...nodes.map(node => node.position.y));
  const maxX = Math.max(...nodes.map(node => node.position.x + NODE_WIDTH));
  const maxY = Math.max(
    ...nodes.map(node => node.position.y + nodeHeight(node))
  );
  const contentWidth = Math.max(1, maxX - minX);
  const contentHeight = Math.max(1, maxY - minY);
  const zoom = Math.min(
    1.15,
    Math.max(
      MIN_ZOOM,
      Math.min(
        (bounds.width - 120) / contentWidth,
        (bounds.height - 120) / contentHeight
      )
    )
  );
  viewport.zoom = zoom;
  viewport.x = (bounds.width - contentWidth * zoom) / 2 - minX * zoom;
  viewport.y = (bounds.height - contentHeight * zoom) / 2 - minY * zoom;
};

const autoArrange = () => {
  const trigger = draft.definition.nodes.find(node => node.type === 'trigger');
  if (!trigger) return;
  const levels = new Map([[trigger.id, 0]]);
  const queue = [trigger.id];
  while (queue.length) {
    const sourceId = queue.shift();
    const nextLevel = levels.get(sourceId) + 1;
    draft.definition.edges
      .filter(edge => edge.source === sourceId)
      .forEach(edge => {
        if (!levels.has(edge.target)) {
          levels.set(edge.target, nextLevel);
          queue.push(edge.target);
        }
      });
  }

  const maxLevel = Math.max(0, ...levels.values());
  draft.definition.nodes.forEach(node => {
    if (!levels.has(node.id)) levels.set(node.id, maxLevel + 1);
  });
  const groups = draft.definition.nodes.reduce((collection, node) => {
    const level = levels.get(node.id);
    if (!collection.has(level)) collection.set(level, []);
    collection.get(level).push(node);
    return collection;
  }, new Map());
  groups.forEach((nodes, level) => {
    nodes.forEach((node, index) => {
      node.position.x = 80 + level * 340;
      node.position.y = 80 + index * 190;
    });
  });
  nextTick(fitView);
};

const updateTemplate = templateKey => {
  const [templateName, language] = templateKey.split('|');
  const template = approvedTemplates.value.find(
    item => item.name === templateName && item.language === language
  );
  if (!selectedNode.value) return;
  const previousButtonIds = (selectedNode.value.config.buttons || []).map(
    button => button.id
  );
  draft.definition.edges = draft.definition.edges.filter(
    edge =>
      edge.source !== selectedNode.value.id ||
      !previousButtonIds.includes(edge.source_handle)
  );

  if (!template || !isStudioTemplateSupported(template)) {
    Object.assign(selectedNode.value.config, {
      template_name: '',
      language: '',
      category: '',
      preview_text: '',
      buttons: [],
      processed_params: {},
    });
    return;
  }
  const body = template.components?.find(
    component => component.type === 'BODY'
  );
  const buttons = templateQuickReplies(template);
  Object.assign(selectedNode.value.config, {
    template_name: template.name,
    language: template.language,
    category: template.category,
    preview_text: body?.text || template.name,
    buttons,
    processed_params: hydrateStudioTemplateParameters(
      template,
      {},
      {
        quickReplies: buttons,
      }
    ),
  });
};

const addReplyButton = () => {
  if (!selectedNode.value || selectedNode.value.config.buttons.length >= 3) {
    return;
  }
  selectedNode.value.config.buttons.push({
    id: createId('reply'),
    title: '',
  });
};

const removeReplyButton = index => {
  const button = selectedNode.value.config.buttons[index];
  removeOutgoingEdge(selectedNode.value.id, button.id);
  selectedNode.value.config.buttons.splice(index, 1);
};

const requestClose = () => {
  if (props.isSaving || props.isPublishing) return;
  if (hasUnsavedChanges.value) {
    discardDialogRef.value?.open();
    return;
  }
  emit('close');
};

const discardChangesAndClose = () => {
  discardDialogRef.value?.close();
  emit('close');
};

const handleEditorKeydown = event => {
  if (event.key === 'Escape') {
    if (pendingConnection.value || selectionBox.value) {
      pendingConnection.value = null;
      selectionBox.value = null;
    } else if (selectedEdge.value || selectedNodeIds.value.length) {
      clearSelection();
    } else requestClose();
    return;
  }
  const isTyping = ['INPUT', 'TEXTAREA', 'SELECT'].includes(
    event.target.tagName
  );
  if (!isTyping && ['Backspace', 'Delete'].includes(event.key)) {
    if (selectedEdge.value) removeEdge(selectedEdge.value.id);
    else if (hasMultipleSelectedNodes.value) deleteSelectedNodes();
    else if (selectedNode.value?.type !== 'trigger') deleteSelectedNode();
  }
};

onMounted(() => nextTick(fitView));

onBeforeUnmount(() => {
  window.removeEventListener('pointermove', moveInteraction);
  window.removeEventListener('pointerup', stopInteraction);
  window.removeEventListener('pointercancel', stopInteraction);
});

const preparePayload = () => ({
  name: draft.name,
  description: draft.description,
  inbox_id: draft.inbox_id,
  trigger_type: draft.trigger_type,
  trigger_config: draft.trigger_config,
  definition: draft.definition,
});
</script>

<template>
  <TeleportWithDirection to="body">
    <div
      class="fixed inset-0 z-[100] flex flex-col bg-n-surface-1"
      role="dialog"
      aria-modal="true"
      :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TITLE')"
      @keydown="handleEditorKeydown"
    >
      <header
        class="flex min-h-16 flex-wrap items-center justify-between gap-3 border-b border-n-weak px-4 py-3 sm:px-5"
      >
        <div class="flex min-w-0 items-center gap-3">
          <button
            type="button"
            class="flex size-11 shrink-0 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="isSaving || isPublishing"
            :aria-label="t('WHATSAPP_CLOUD_STUDIO.CLOSE')"
            @click="requestClose"
          >
            <span class="i-lucide-arrow-left size-5" aria-hidden="true" />
          </button>
          <div class="min-w-0">
            <input
              v-model="draft.name"
              class="reset-base !mb-0 h-8 w-full max-w-md border-0 bg-transparent text-lg font-semibold text-n-slate-12 outline-none"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.FLOW_NAME')"
            />
            <div class="flex items-center gap-2 text-xs text-n-slate-9">
              <span
                class="size-2 rounded-full"
                :class="
                  draft.status === 'active' ? 'bg-n-teal-9' : 'bg-n-slate-8'
                "
                aria-hidden="true"
              />
              <span>
                {{ flowStatusLabel(draft.status) }}
              </span>
            </div>
          </div>
        </div>
        <div class="flex w-full items-center justify-end gap-2 sm:w-auto">
          <Button
            :label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SAVE_DRAFT')"
            color="slate"
            variant="outline"
            :is-loading="isSaving"
            :disabled="isSaving || isPublishing"
            @click="emit('save', preparePayload())"
          />
          <Button
            :label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.PUBLISH')"
            icon="i-lucide-rocket"
            :is-loading="isPublishing"
            :disabled="
              isSaving ||
              isPublishing ||
              flowHasUnsupportedTemplates ||
              flowHasIncompleteTemplateParameters
            "
            @click="emit('publish', preparePayload())"
          />
        </div>
      </header>

      <div
        class="grid min-h-0 flex-1 grid-cols-1 grid-rows-[auto_minmax(26rem,1fr)_auto] overflow-x-hidden overflow-y-auto sm:grid-rows-[auto_minmax(32rem,1fr)_auto] lg:grid-cols-[13rem_minmax(40rem,1fr)_18rem] lg:grid-rows-1 xl:grid-cols-[15rem_minmax(0,1fr)_20rem]"
      >
        <aside
          class="border-b border-n-weak bg-n-alpha-1 p-4 lg:overflow-y-auto lg:border-b-0 lg:border-r"
        >
          <h2
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-9"
          >
            {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.BLOCKS') }}
          </h2>
          <div
            class="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-1"
          >
            <button
              v-for="nodeType in nodeTypes"
              :key="nodeType.type"
              type="button"
              class="flex min-h-11 w-full items-center gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-3 text-left text-sm font-medium text-n-slate-12 transition hover:border-n-strong hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              @click="addNode(nodeType.type)"
            >
              <span
                class="flex size-8 items-center justify-center rounded-lg bg-n-blue-3 text-n-blue-11"
              >
                <span
                  class="size-4"
                  :class="nodeType.icon"
                  aria-hidden="true"
                />
              </span>
              <span>
                {{ nodeTypeLabel(nodeType.type) }}
              </span>
            </button>
          </div>

          <div
            class="mt-4 rounded-xl border border-n-weak bg-n-alpha-2 p-3 lg:mt-6"
          >
            <h3
              class="flex items-center gap-2 text-xs font-semibold text-n-slate-12"
            >
              <span class="i-lucide-link-2 size-3.5" aria-hidden="true" />
              {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONNECT_HELP_TITLE') }}
            </h3>
            <p class="mt-1 text-xs leading-5 text-n-slate-9">
              {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONNECT_HELP') }}
            </p>
          </div>
        </aside>

        <div
          ref="canvasRef"
          class="relative min-h-[26rem] min-w-0 overflow-hidden bg-n-surface-2 sm:min-h-[32rem] lg:min-h-0"
        >
          <Transition
            enter-active-class="motion-safe:transition motion-safe:duration-200 motion-safe:ease-out"
            enter-from-class="-translate-y-2 opacity-0"
            enter-to-class="translate-y-0 opacity-100"
            leave-active-class="motion-safe:transition motion-safe:duration-150 motion-safe:ease-in"
            leave-from-class="translate-y-0 opacity-100"
            leave-to-class="-translate-y-2 opacity-0"
          >
            <div
              v-if="pendingConnection"
              class="absolute left-4 top-4 z-20 inline-flex items-center gap-2 rounded-lg bg-n-blue-9 px-3 py-2 text-xs font-medium text-white shadow-lg motion-reduce:transform-none"
            >
              <span
                class="i-lucide-mouse-pointer-click size-4"
                aria-hidden="true"
              />
              {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SELECT_TARGET') }}
              <button
                type="button"
                class="ml-1 flex size-11 items-center justify-center rounded-lg transition-colors hover:bg-white/20 motion-reduce:transition-none"
                :aria-label="t('WHATSAPP_CLOUD_STUDIO.CANCEL')"
                @click="pendingConnection = null"
              >
                <span class="i-lucide-x size-3" aria-hidden="true" />
              </button>
            </div>
          </Transition>

          <Transition
            enter-active-class="motion-safe:transition motion-safe:duration-200 motion-safe:ease-out"
            enter-from-class="-translate-y-2 opacity-0"
            enter-to-class="translate-y-0 opacity-100"
            leave-active-class="motion-safe:transition motion-safe:duration-150"
            leave-from-class="opacity-100"
            leave-to-class="opacity-0"
          >
            <div
              v-if="hasMultipleSelectedNodes"
              class="absolute left-4 top-4 z-20 flex items-center gap-3 rounded-xl border border-n-blue-7 bg-n-solid-1 px-3 py-2 text-xs text-n-slate-11 shadow-lg"
            >
              <span
                class="flex size-8 items-center justify-center rounded-lg bg-n-blue-3 text-n-blue-11"
              >
                <span
                  class="i-lucide-mouse-pointer-2 size-4"
                  aria-hidden="true"
                />
              </span>
              <span>
                <strong class="block text-n-slate-12">
                  {{
                    t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SELECTED_BLOCKS', {
                      count: selectedNodeIds.length,
                    })
                  }}
                </strong>
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.GROUP_DRAG_HINT') }}
              </span>
              <button
                type="button"
                class="flex size-9 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
                :aria-label="
                  t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CLEAR_SELECTION')
                "
                @click="clearSelection"
              >
                <span class="i-lucide-x size-4" aria-hidden="true" />
              </button>
            </div>
          </Transition>

          <div
            class="absolute bottom-4 right-4 z-20 flex items-center overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-lg"
          >
            <button
              type="button"
              class="flex size-11 items-center justify-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-40"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.ZOOM_OUT')"
              :disabled="viewport.zoom <= MIN_ZOOM"
              @click="zoomOut"
            >
              <span class="i-lucide-minus size-4" aria-hidden="true" />
            </button>
            <span
              class="min-w-14 border-x border-n-weak px-2 text-center text-xs font-medium text-n-slate-11"
            >
              {{ zoomPercentage }}
            </span>
            <button
              type="button"
              class="flex size-11 items-center justify-center text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-40"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.ZOOM_IN')"
              :disabled="viewport.zoom >= MAX_ZOOM"
              @click="zoomIn"
            >
              <span class="i-lucide-plus size-4" aria-hidden="true" />
            </button>
            <button
              type="button"
              class="flex size-11 items-center justify-center border-l border-n-weak text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.FIT_VIEW')"
              @click="fitView"
            >
              <span class="i-lucide-scan size-4" aria-hidden="true" />
            </button>
            <button
              type="button"
              class="flex size-11 items-center justify-center border-l border-n-weak text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
              :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.AUTO_ARRANGE')"
              @click="autoArrange"
            >
              <span class="i-lucide-wand-sparkles size-4" aria-hidden="true" />
            </button>
          </div>

          <div
            class="pointer-events-none absolute bottom-4 left-4 z-10 hidden items-center gap-2 rounded-lg bg-n-solid-1/90 px-3 py-2 text-[0.7rem] text-n-slate-9 shadow-sm xl:flex"
          >
            <span class="i-lucide-move size-3.5" aria-hidden="true" />
            {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.PAN_HINT') }}
          </div>

          <svg
            ref="svgRef"
            class="block size-full min-h-[38rem] select-none touch-none sm:min-h-[44rem] lg:min-h-full"
            :aria-label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CANVAS')"
            tabindex="0"
            @pointerdown="startCanvasPan"
            @contextmenu.prevent
            @wheel.prevent="handleCanvasWheel"
          >
            <defs>
              <pattern
                id="whatsapp-flow-grid"
                width="24"
                height="24"
                patternUnits="userSpaceOnUse"
              >
                <circle cx="1" cy="1" r="1" class="fill-n-slate-5" />
              </pattern>
              <marker
                id="whatsapp-flow-arrow"
                markerWidth="8"
                markerHeight="8"
                refX="7"
                refY="4"
                orient="auto"
              >
                <path d="M 0 0 L 8 4 L 0 8 z" class="fill-n-slate-8" />
              </marker>
            </defs>
            <g :transform="viewportTransform">
              <rect
                x="-5000"
                y="-5000"
                width="10000"
                height="10000"
                fill="url(#whatsapp-flow-grid)"
                data-flow-canvas-background="true"
              />

              <rect
                v-if="selectionBoxGeometry"
                :x="selectionBoxGeometry.x"
                :y="selectionBoxGeometry.y"
                :width="selectionBoxGeometry.width"
                :height="selectionBoxGeometry.height"
                rx="8"
                class="pointer-events-none fill-n-blue-3 stroke-n-brand"
                stroke-width="1.5"
                stroke-dasharray="6 4"
              />

              <g v-for="edge in draft.definition.edges" :key="edge.id">
                <path
                  :d="edgePath(edge)"
                  fill="none"
                  class="cursor-pointer stroke-transparent"
                  stroke-width="18"
                  @click.stop="selectEdge(edge.id)"
                />
                <path
                  :d="edgePath(edge)"
                  fill="none"
                  class="pointer-events-none transition-colors"
                  :class="
                    selectedEdgeId === edge.id
                      ? 'stroke-n-brand'
                      : 'stroke-n-slate-8'
                  "
                  stroke-width="2.5"
                  marker-end="url(#whatsapp-flow-arrow)"
                />
              </g>

              <path
                v-if="pendingConnectionPath"
                :d="pendingConnectionPath"
                fill="none"
                class="pointer-events-none stroke-n-brand"
                stroke-width="2.5"
                stroke-dasharray="8 6"
              >
                <animate
                  attributeName="stroke-dashoffset"
                  from="28"
                  to="0"
                  dur="0.8s"
                  repeatCount="indefinite"
                />
              </path>

              <g
                v-for="node in draft.definition.nodes"
                :key="node.id"
                :transform="nodeTransform(node)"
              >
                <rect
                  :width="NODE_WIDTH"
                  :height="nodeHeight(node)"
                  rx="16"
                  class="pointer-events-none fill-n-solid-1 stroke-2"
                  :class="
                    selectedNodeIds.includes(node.id)
                      ? 'stroke-n-brand'
                      : 'stroke-n-slate-6'
                  "
                />
                <foreignObject
                  x="0"
                  y="0"
                  :width="NODE_WIDTH"
                  :height="nodeHeight(node)"
                >
                  <div
                    class="h-full cursor-grab overflow-hidden rounded-2xl bg-transparent active:cursor-grabbing"
                    :data-test-id="`flow-node-${node.id}`"
                    role="button"
                    :aria-pressed="selectedNodeIds.includes(node.id)"
                    tabindex="0"
                    @pointerdown.stop="startNodeDrag($event, node)"
                    @click.stop="handleNodeClick($event, node.id)"
                    @keydown.enter.stop="selectNode(node.id, $event)"
                  >
                    <div
                      class="flex h-14 w-full items-center gap-3 border-b border-n-weak px-3 text-left"
                    >
                      <span
                        class="flex size-8 shrink-0 items-center justify-center rounded-lg"
                        :class="nodeTone(node)"
                      >
                        <span
                          class="size-4"
                          :class="nodeIcon(node)"
                          aria-hidden="true"
                        />
                      </span>
                      <span class="min-w-0">
                        <span
                          class="block text-sm font-semibold text-n-slate-12"
                        >
                          {{ nodeTitle(node) }}
                        </span>
                        <span class="block truncate text-xs text-n-slate-9">
                          {{ nodeSubtitle(node) }}
                        </span>
                      </span>
                      <span
                        class="i-lucide-grip-vertical ml-auto size-4 shrink-0 text-n-slate-7"
                        aria-hidden="true"
                      />
                    </div>
                    <div
                      v-if="
                        node.type === 'message' && node.config.buttons?.length
                      "
                      class="space-y-1 p-2"
                    >
                      <div
                        v-for="button in node.config.buttons"
                        :key="button.id"
                        class="flex h-7 items-center rounded-md bg-n-alpha-2 px-2 text-xs text-n-slate-11"
                      >
                        <span
                          class="i-lucide-reply mr-1.5 size-3"
                          aria-hidden="true"
                        />
                        <span class="truncate">
                          {{
                            button.title ||
                            t(
                              'WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.UNTITLED_BUTTON'
                            )
                          }}
                        </span>
                      </div>
                    </div>
                    <div
                      v-else
                      class="line-clamp-3 px-3 py-3 text-xs leading-5 text-n-slate-10"
                    >
                      {{ nodeSubtitle(node) }}
                    </div>
                  </div>
                </foreignObject>

                <circle
                  cx="0"
                  cy="58"
                  r="8"
                  class="cursor-crosshair fill-n-solid-1 stroke-n-brand hover:fill-n-blue-3"
                  stroke-width="3"
                  role="button"
                  :data-flow-target="node.id"
                  :aria-label="
                    t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TARGET_HANDLE')
                  "
                  tabindex="0"
                  @pointerup.stop="finishConnection(node.id)"
                  @click="finishConnection(node.id)"
                  @keydown.enter="finishConnection(node.id)"
                />
                <circle
                  v-if="
                    node.type !== 'end' &&
                    node.type !== 'condition' &&
                    !(node.type === 'message' && node.config.buttons?.length)
                  "
                  :cx="NODE_WIDTH"
                  cy="58"
                  r="8"
                  class="cursor-crosshair fill-n-solid-1 stroke-n-brand hover:fill-n-blue-3"
                  stroke-width="3"
                  role="button"
                  :aria-label="
                    t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SOURCE_HANDLE')
                  "
                  tabindex="0"
                  @pointerdown.stop="startConnectionDrag($event, node.id)"
                  @keydown.enter="startConnection(node.id)"
                />
                <circle
                  v-for="conditionHandle in node.type === 'condition'
                    ? ['true', 'false']
                    : []"
                  :key="`${node.id}-${conditionHandle}`"
                  :cx="NODE_WIDTH"
                  :cy="handleY(node, conditionHandle) - node.position.y"
                  r="6"
                  class="cursor-crosshair fill-n-solid-1 stroke-n-brand hover:fill-n-blue-3"
                  stroke-width="3"
                  role="button"
                  :aria-label="conditionHandleLabel(conditionHandle)"
                  tabindex="0"
                  @pointerdown.stop="
                    startConnectionDrag($event, node.id, conditionHandle)
                  "
                  @keydown.enter="startConnection(node.id, conditionHandle)"
                />
                <circle
                  v-for="button in node.type === 'message'
                    ? node.config.buttons || []
                    : []"
                  :key="`${node.id}-${button.id}`"
                  :cx="NODE_WIDTH"
                  :cy="handleY(node, button.id) - node.position.y"
                  r="6"
                  class="cursor-crosshair fill-n-solid-1 stroke-n-brand hover:fill-n-blue-3"
                  stroke-width="3"
                  role="button"
                  :aria-label="
                    t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.BUTTON_HANDLE', {
                      title: button.title,
                    })
                  "
                  tabindex="0"
                  @pointerdown.stop="
                    startConnectionDrag($event, node.id, button.id)
                  "
                  @keydown.enter="startConnection(node.id, button.id)"
                />
              </g>

              <foreignObject
                v-if="selectedEdge"
                :x="edgeMidpoint(selectedEdge).x - 20"
                :y="edgeMidpoint(selectedEdge).y - 20"
                width="40"
                height="40"
              >
                <animate
                  attributeName="opacity"
                  from="0"
                  to="1"
                  dur="0.18s"
                  fill="freeze"
                />
                <button
                  type="button"
                  class="flex size-10 items-center justify-center rounded-full border border-n-ruby-7 bg-n-solid-1 text-n-ruby-11 shadow-lg transition hover:scale-105 hover:bg-n-ruby-3 motion-reduce:transform-none motion-reduce:transition-none"
                  :aria-label="
                    t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DELETE_CONNECTION')
                  "
                  @click.stop="removeEdge(selectedEdge.id)"
                >
                  <span class="i-lucide-unlink size-4" aria-hidden="true" />
                </button>
              </foreignObject>
            </g>
          </svg>
        </div>

        <aside
          class="overflow-y-auto border-t border-n-weak bg-n-alpha-1 p-4 lg:border-l lg:border-t-0"
        >
          <div v-if="hasMultipleSelectedNodes" class="flex h-full flex-col">
            <div
              class="flex size-10 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
            >
              <span class="i-lucide-box-select size-5" aria-hidden="true" />
            </div>
            <h2 class="mt-4 text-sm font-semibold text-n-slate-12">
              {{
                t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SELECTED_BLOCKS', {
                  count: selectedNodeIds.length,
                })
              }}
            </h2>
            <p class="mt-2 text-xs leading-5 text-n-slate-9">
              {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.MULTI_SELECT_HELP') }}
            </p>
            <div class="mt-5 rounded-xl border border-n-weak bg-n-alpha-2 p-3">
              <div
                v-for="node in selectedNodes"
                :key="node.id"
                class="flex items-center gap-2 py-1.5 text-xs text-n-slate-11"
              >
                <span
                  class="size-3.5"
                  :class="nodeIcon(node)"
                  aria-hidden="true"
                />
                <span class="truncate">{{ nodeTitle(node) }}</span>
              </div>
            </div>
            <div class="mt-5 grid gap-2">
              <Button
                type="button"
                color="slate"
                variant="outline"
                icon="i-lucide-x"
                :label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CLEAR_SELECTION')"
                @click="clearSelection"
              />
              <Button
                v-if="selectedNodes.some(node => node.type !== 'trigger')"
                type="button"
                color="ruby"
                variant="outline"
                icon="i-lucide-trash-2"
                :label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DELETE_SELECTED')"
                @click="deleteSelectedNodes"
              />
            </div>
          </div>
          <template v-else-if="selectedNode">
            <div class="flex items-start justify-between gap-2">
              <div>
                <h2 class="text-sm font-semibold text-n-slate-12">
                  {{ nodeTitle(selectedNode) }}
                </h2>
                <p class="mt-1 text-xs text-n-slate-9">
                  {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.NODE_SETTINGS') }}
                </p>
              </div>
              <div
                v-if="selectedNode.type !== 'trigger'"
                class="flex items-center gap-1"
              >
                <button
                  type="button"
                  class="flex size-11 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  :aria-label="
                    t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DUPLICATE_NODE')
                  "
                  @click="duplicateSelectedNode"
                >
                  <span class="i-lucide-copy-plus size-4" aria-hidden="true" />
                </button>
                <button
                  type="button"
                  class="flex size-11 items-center justify-center rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
                  :aria-label="
                    t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DELETE_NODE')
                  "
                  @click="deleteSelectedNode"
                >
                  <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
                </button>
              </div>
            </div>

            <div v-if="selectedNode.type === 'trigger'" class="mt-5 space-y-4">
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TRIGGER') }}
                <StudioSelect v-model="draft.trigger_type">
                  <option value="keyword">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.KEYWORD') }}
                  </option>
                  <option value="any_message">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.ANY_MESSAGE') }}
                  </option>
                </StudioSelect>
              </label>
              <label
                v-if="draft.trigger_type === 'keyword'"
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.KEYWORDS') }}
                <input
                  :value="draft.trigger_config.keywords?.join(', ')"
                  class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                  :placeholder="
                    t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.KEYWORDS_PLACEHOLDER')
                  "
                  @input="
                    draft.trigger_config.keywords = $event.target.value
                      .split(',')
                      .map(item => item.trim())
                      .filter(Boolean)
                  "
                />
              </label>
            </div>

            <div
              v-else-if="selectedNode.type === 'message'"
              class="mt-5 space-y-4"
            >
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.MESSAGE_MODE') }}
                <StudioSelect v-model="selectedNode.config.mode">
                  <option value="session">
                    {{
                      t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SESSION_MESSAGE')
                    }}
                  </option>
                  <option value="template">
                    {{
                      t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TEMPLATE_MESSAGE')
                    }}
                  </option>
                </StudioSelect>
              </label>
              <div
                class="rounded-lg border p-3 text-xs leading-5"
                :class="
                  selectedNode.config.mode === 'session'
                    ? 'border-n-amber-7 bg-n-amber-2 text-n-amber-11'
                    : 'border-n-teal-7 bg-n-teal-2 text-n-teal-11'
                "
              >
                {{
                  selectedNode.config.mode === 'session'
                    ? t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SESSION_WARNING')
                    : t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TEMPLATE_INFO')
                }}
              </div>
              <label
                v-if="selectedNode.config.mode === 'session'"
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.MESSAGE_TEXT') }}
                <textarea
                  v-model="selectedNode.config.text"
                  rows="6"
                  class="reset-base !mb-0 min-h-32 resize-y rounded-xl border border-n-strong bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                />
              </label>
              <label
                v-else
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TEMPLATE') }}
                <StudioSelect
                  :model-value="selectedTemplateKey"
                  @update:model-value="updateTemplate"
                >
                  <option value="">
                    {{
                      t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.SELECT_TEMPLATE')
                    }}
                  </option>
                  <option
                    v-for="template in approvedTemplates"
                    :key="`${template.name}-${template.language}`"
                    :value="`${template.name}|${template.language}`"
                    :disabled="!isStudioTemplateSupported(template)"
                  >
                    {{ selectableTemplateLabel(template) }}
                  </option>
                </StudioSelect>
              </label>

              <div
                v-if="selectedTemplateUnsupported"
                class="rounded-lg border border-n-amber-7 bg-n-amber-2 p-3 text-xs leading-5 text-n-amber-11"
              >
                {{
                  t(
                    'WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.UNSUPPORTED_SELECTED'
                  )
                }}
              </div>

              <StudioTemplateParameterFields
                v-if="
                  selectedNode.config.mode === 'template' && selectedTemplate
                "
                v-model="selectedNode.config.processed_params"
                :template="selectedTemplate"
              />

              <div
                v-if="selectedTemplateParametersIncomplete"
                class="rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3 text-xs leading-5 text-n-ruby-11"
              >
                {{
                  t(
                    'WHATSAPP_CLOUD_STUDIO.TEMPLATE_PARAMETERS.INCOMPLETE_SELECTED'
                  )
                }}
              </div>

              <div v-if="selectedNode.config.mode === 'session'">
                <div class="flex items-center justify-between gap-2">
                  <span class="text-xs font-medium text-n-slate-11">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.REPLY_BUTTONS') }}
                  </span>
                  <button
                    v-if="selectedNode.config.buttons.length < 3"
                    type="button"
                    class="inline-flex min-h-11 items-center rounded-lg px-2 text-xs font-medium text-n-blue-11 hover:bg-n-blue-3 hover:underline"
                    @click="addReplyButton"
                  >
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.ADD_BUTTON') }}
                  </button>
                </div>
                <div class="mt-2 space-y-2">
                  <div
                    v-for="(button, index) in selectedNode.config.buttons"
                    :key="button.id"
                    class="grid grid-cols-[1fr_auto] gap-2 rounded-lg border border-n-weak bg-n-alpha-2 p-2"
                  >
                    <input
                      v-model="button.title"
                      class="reset-base !mb-0 h-9 rounded-md border border-n-strong bg-n-alpha-1 px-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                      :placeholder="
                        t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.BUTTON_TITLE')
                      "
                    />
                    <button
                      type="button"
                      class="flex size-11 items-center justify-center rounded-md text-n-ruby-11 hover:bg-n-ruby-3"
                      :aria-label="
                        t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.REMOVE_BUTTON')
                      "
                      @click="removeReplyButton(index)"
                    >
                      <span class="i-lucide-x size-4" aria-hidden="true" />
                    </button>
                    <code
                      class="col-span-2 truncate text-[0.65rem] text-n-slate-9"
                    >
                      {{ button.id }}
                    </code>
                  </div>
                </div>
              </div>
            </div>

            <div v-else-if="selectedNode.type === 'wait'" class="mt-5">
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DURATION_MINUTES') }}
                <input
                  v-model.number="selectedNode.config.duration"
                  type="number"
                  min="1"
                  max="43200"
                  class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                />
              </label>
            </div>

            <div
              v-else-if="selectedNode.type === 'condition'"
              class="mt-5 space-y-3"
            >
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.FIELD') }}
                <StudioSelect v-model="selectedNode.config.field">
                  <option value="last_button_id">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.LAST_BUTTON') }}
                  </option>
                  <option value="name">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTACT_NAME') }}
                  </option>
                  <option value="email">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTACT_EMAIL') }}
                  </option>
                  <option value="phone_number">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTACT_PHONE') }}
                  </option>
                </StudioSelect>
              </label>
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.OPERATOR') }}
                <StudioSelect v-model="selectedNode.config.operator">
                  <option value="equals">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.EQUALS') }}
                  </option>
                  <option value="not_equals">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.NOT_EQUALS') }}
                  </option>
                  <option value="contains">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONTAINS') }}
                  </option>
                  <option value="present">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.PRESENT') }}
                  </option>
                </StudioSelect>
              </label>
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.VALUE') }}
                <input
                  v-model="selectedNode.config.value"
                  class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                />
              </label>
              <div class="grid grid-cols-2 gap-2 pt-1 text-xs">
                <button
                  type="button"
                  class="min-h-11 rounded-lg border border-n-teal-7 bg-n-teal-2 px-2 py-2 font-medium text-n-teal-11"
                  @click="startConnection(selectedNode.id, 'true')"
                >
                  {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.TRUE_BRANCH') }}
                </button>
                <button
                  type="button"
                  class="min-h-11 rounded-lg border border-n-ruby-7 bg-n-ruby-2 px-2 py-2 font-medium text-n-ruby-11"
                  @click="startConnection(selectedNode.id, 'false')"
                >
                  {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.FALSE_BRANCH') }}
                </button>
              </div>
            </div>

            <div
              v-else-if="selectedNode.type === 'action'"
              class="mt-5 space-y-3"
            >
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.ACTION') }}
                <StudioSelect v-model="selectedNode.config.action">
                  <option value="add_label">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.ADD_LABEL') }}
                  </option>
                  <option value="remove_label">
                    {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.REMOVE_LABEL') }}
                  </option>
                  <option value="open_conversation">
                    {{
                      t('WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.OPEN_CONVERSATION')
                    }}
                  </option>
                  <option value="resolve_conversation">
                    {{
                      t(
                        'WHATSAPP_CLOUD_STUDIO.FLOWS.ACTIONS.RESOLVE_CONVERSATION'
                      )
                    }}
                  </option>
                </StudioSelect>
              </label>
              <label
                v-if="
                  ['add_label', 'remove_label'].includes(
                    selectedNode.config.action
                  )
                "
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.LABEL') }}
                <input
                  v-model="selectedNode.config.value"
                  class="reset-base !mb-0 h-11 rounded-xl border border-n-strong bg-n-alpha-1 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                />
              </label>
            </div>

            <div class="mt-6 border-t border-n-weak pt-4">
              <label
                class="flex flex-col gap-1 text-xs font-medium text-n-slate-11"
              >
                {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DESCRIPTION') }}
                <textarea
                  v-model="draft.description"
                  rows="3"
                  class="reset-base !mb-0 min-h-24 resize-y rounded-xl border border-n-strong bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand"
                />
              </label>
            </div>
          </template>
          <div v-else-if="selectedEdge" class="flex h-full flex-col">
            <div
              class="flex size-10 items-center justify-center rounded-xl bg-n-ruby-3 text-n-ruby-11"
            >
              <span class="i-lucide-unlink size-5" aria-hidden="true" />
            </div>
            <h2 class="mt-4 text-sm font-semibold text-n-slate-12">
              {{ t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONNECTION_SELECTED') }}
            </h2>
            <p class="mt-2 text-xs leading-5 text-n-slate-9">
              {{
                t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.CONNECTION_DESCRIPTION')
              }}
            </p>
            <Button
              class="mt-5 w-full"
              type="button"
              color="ruby"
              variant="outline"
              icon="i-lucide-trash-2"
              :label="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DELETE_CONNECTION')"
              @click="removeEdge(selectedEdge.id)"
            />
          </div>
        </aside>
      </div>
    </div>

    <Dialog
      ref="discardDialogRef"
      type="alert"
      width="sm"
      :title="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DISCARD_TITLE')"
      :description="t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DISCARD_CONFIRM')"
      :cancel-button-label="
        t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.KEEP_EDITING')
      "
      :confirm-button-label="
        t('WHATSAPP_CLOUD_STUDIO.FLOWS.EDITOR.DISCARD_CHANGES')
      "
      @confirm="discardChangesAndClose"
    />
  </TeleportWithDirection>
</template>
