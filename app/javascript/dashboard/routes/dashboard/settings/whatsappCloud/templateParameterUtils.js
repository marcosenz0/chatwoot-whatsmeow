const VARIABLE_PATTERN = /\{\{([^}]+)\}\}/g;
const SUPPORTED_COMPONENT_TYPES = new Set([
  'HEADER',
  'BODY',
  'FOOTER',
  'BUTTONS',
]);
const SUPPORTED_HEADER_FORMATS = new Set([
  '',
  'TEXT',
  'IMAGE',
  'VIDEO',
  'DOCUMENT',
]);
const SUPPORTED_BUTTON_TYPES = new Set([
  'QUICK_REPLY',
  'URL',
  'PHONE_NUMBER',
  'COPY_CODE',
]);
const MEDIA_HEADER_FORMATS = new Set(['IMAGE', 'VIDEO', 'DOCUMENT']);

const normalizeType = value => value?.toString().toUpperCase() || '';

export const templateComponent = (template, type) =>
  template?.components?.find(
    component => normalizeType(component.type) === normalizeType(type)
  );

export const templateVariableKeys = text => {
  const keys = [...(text || '').matchAll(VARIABLE_PATTERN)].map(match =>
    match[1].trim()
  );
  return [...new Set(keys)].filter(Boolean);
};

export const templateBodyText = template =>
  templateComponent(template, 'BODY')?.text || '';

export const templateHeader = template => {
  const component = templateComponent(template, 'HEADER');
  const format = normalizeType(component?.format);
  return {
    component,
    format,
    isMedia: MEDIA_HEADER_FORMATS.has(format),
    variableKeys: templateVariableKeys(component?.text),
  };
};

export const templateQuickReplies = template => {
  const buttons = templateComponent(template, 'BUTTONS')?.buttons || [];
  return buttons
    .map((button, index) => ({ ...button, template_index: index }))
    .filter(button => normalizeType(button.type) === 'QUICK_REPLY')
    .map(button => ({
      id: `template_reply_${button.template_index}`,
      title: button.text,
      template_index: button.template_index,
    }));
};

export const isStudioTemplateSupported = template => {
  if (!template || normalizeType(template.category) === 'AUTHENTICATION') {
    return false;
  }

  const components = Array.isArray(template.components)
    ? template.components
    : [];
  if (!templateComponent(template, 'BODY')) return false;
  if (
    components.some(
      component => !SUPPORTED_COMPONENT_TYPES.has(normalizeType(component.type))
    )
  ) {
    return false;
  }

  const header = templateHeader(template);
  if (!SUPPORTED_HEADER_FORMATS.has(header.format)) return false;

  const buttons = templateComponent(template, 'BUTTONS')?.buttons || [];
  return buttons.every(button =>
    SUPPORTED_BUTTON_TYPES.has(normalizeType(button.type))
  );
};

const buildSection = keys =>
  Object.fromEntries(keys.map(variableKey => [variableKey, '']));

export const buildStudioTemplateParameters = (
  template,
  { quickReplies = [] } = {}
) => {
  const parameters = {};
  const header = templateHeader(template);
  const bodyVariableKeys = templateVariableKeys(templateBodyText(template));

  if (header.isMedia) {
    parameters.header = {
      media_url: '',
      media_type: header.format.toLowerCase(),
    };
    if (header.format === 'DOCUMENT') {
      parameters.header.media_name = '';
    }
  } else if (header.variableKeys.length) {
    parameters.header = buildSection(header.variableKeys);
  }

  if (bodyVariableKeys.length) {
    parameters.body = buildSection(bodyVariableKeys);
  }

  const quickReplyByIndex = new Map(
    quickReplies.map(button => [Number(button.template_index), button])
  );
  const templateButtons = templateComponent(template, 'BUTTONS')?.buttons || [];
  const buttonParameters = templateButtons.flatMap((button, index) => {
    const type = normalizeType(button.type);
    if (type === 'URL' && templateVariableKeys(button.url).length) {
      return [{ type: 'url', index, parameter: '', url: button.url }];
    }
    if (type === 'COPY_CODE') {
      return [{ type: 'copy_code', index, parameter: '' }];
    }
    if (type === 'QUICK_REPLY' && quickReplyByIndex.has(index)) {
      return [
        {
          type: 'quick_reply',
          index,
          payload: quickReplyByIndex.get(index).id,
        },
      ];
    }
    return [];
  });

  if (buttonParameters.length) {
    parameters.buttons = buttonParameters;
  }

  return parameters;
};

const mergeSection = (required, current = {}) =>
  Object.fromEntries(
    Object.entries(required).map(([key, fallback]) => [
      key,
      current[key] ?? fallback,
    ])
  );

export const hydrateStudioTemplateParameters = (
  template,
  current = {},
  options = {}
) => {
  const required = buildStudioTemplateParameters(template, options);
  const hydrated = {};

  if (required.header) {
    hydrated.header = mergeSection(required.header, current.header);
  }
  if (required.body) {
    hydrated.body = mergeSection(required.body, current.body);
  }
  if (required.buttons) {
    const currentButtons = Array.isArray(current.buttons)
      ? current.buttons
      : [];
    hydrated.buttons = required.buttons.map(requiredButton => {
      const savedButton = currentButtons.find(
        button =>
          Number(button?.index) === Number(requiredButton.index) &&
          button?.type === requiredButton.type
      );
      return {
        ...requiredButton,
        ...savedButton,
        index: requiredButton.index,
        type: requiredButton.type,
        payload: requiredButton.payload || savedButton?.payload,
      };
    });
  }

  return hydrated;
};

const validMediaUrl = (value, allowLiquid) => {
  if (allowLiquid && value?.includes('{{')) return true;
  try {
    return ['http:', 'https:'].includes(new URL(value).protocol);
  } catch {
    return false;
  }
};

export const templateParametersComplete = (
  parameters,
  { allowLiquid = false } = {}
) => {
  const header = parameters?.header || {};
  const headerComplete = Object.entries(header).every(([key, value]) => {
    if (['media_type', 'media_name'].includes(key)) return true;
    if (key === 'media_url') return validMediaUrl(value, allowLiquid);
    return value?.toString().trim();
  });
  const bodyComplete = Object.values(parameters?.body || {}).every(value =>
    value?.toString().trim()
  );
  const buttons = Array.isArray(parameters?.buttons) ? parameters.buttons : [];
  const buttonsComplete = buttons.every(button => {
    if (button.type === 'quick_reply') {
      return button.payload?.toString().trim();
    }
    if (button.type === 'copy_code') {
      const length = button.parameter?.toString().trim().length || 0;
      return length >= 1 && length <= 15;
    }
    return button.parameter?.toString().trim();
  });

  return headerComplete && bodyComplete && buttonsComplete;
};

export const renderTemplateBody = (template, parameters = {}) =>
  templateBodyText(template).replace(VARIABLE_PATTERN, (match, variable) => {
    const value = parameters.body?.[variable.trim()];
    return value?.toString().trim() ? value : match;
  });
