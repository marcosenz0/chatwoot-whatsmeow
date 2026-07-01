const PHONE_NUMBER_PATTERN =
  /(^|[^\p{L}\p{N}_])(\+?\d(?:[\d(). \t-]*\d){5,})(?=$|[^\p{L}\p{N}_])/gu;

const SKIPPED_TAGS = new Set([
  'A',
  'BUTTON',
  'CODE',
  'PRE',
  'SCRIPT',
  'STYLE',
  'TEXTAREA',
]);

const PHONE_TOKEN_CLASS =
  'skip-context-menu cursor-pointer font-semibold text-n-teal-11 underline decoration-n-teal-9/60 underline-offset-2 transition-colors hover:text-n-teal-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/50';

export const whatsmeowPhoneDigits = value =>
  (value || '').toString().replace(/\D/g, '');

export const normalizeWhatsmeowPhoneNumber = value => {
  const rawValue = (value || '').toString().trim();
  const digits = whatsmeowPhoneDigits(rawValue);

  if (digits.length < 6) return '';
  if (rawValue.startsWith('+')) return `+${digits}`;
  if (!digits.startsWith('55') && [10, 11].includes(digits.length)) {
    return `+55${digits}`;
  }
  if (digits.length >= 10 && digits.length <= 15) return `+${digits}`;

  return digits;
};

export const whatsmeowPhoneParts = text => {
  const parts = [];
  const pattern = new RegExp(PHONE_NUMBER_PATTERN);
  let lastIndex = 0;
  let match = pattern.exec(text);

  while (match !== null) {
    const boundary = match[1] || '';
    const rawNumber = match[2] || '';
    const digitCount = whatsmeowPhoneDigits(rawNumber).length;

    if (digitCount >= 6) {
      const numberStart = match.index + boundary.length;
      const numberEnd = numberStart + rawNumber.length;
      if (numberStart > lastIndex) {
        parts.push({ type: 'text', value: text.slice(lastIndex, numberStart) });
      }

      parts.push({
        type: 'phone',
        value: rawNumber,
        normalizedValue: normalizeWhatsmeowPhoneNumber(rawNumber),
      });
      lastIndex = numberEnd;
    }

    match = pattern.exec(text);
  }

  if (lastIndex < text.length) {
    parts.push({ type: 'text', value: text.slice(lastIndex) });
  }

  return parts.length ? parts : [{ type: 'text', value: text }];
};

const createPhoneNode = (document, part) => {
  const node = document.createElement('span');
  node.className = PHONE_TOKEN_CLASS;
  node.textContent = part.value;
  node.setAttribute('role', 'button');
  node.setAttribute('tabindex', '0');
  node.setAttribute('data-selection-ignore', 'true');
  node.setAttribute('data-whatsmeow-phone-number', part.value);
  node.setAttribute('data-whatsmeow-phone-normalized', part.normalizedValue);
  return node;
};

const replaceTextNode = textNode => {
  const parts = whatsmeowPhoneParts(textNode.textContent || '');
  if (!parts.some(part => part.type === 'phone')) return;

  const fragment = textNode.ownerDocument.createDocumentFragment();
  parts.forEach(part => {
    fragment.appendChild(
      part.type === 'phone'
        ? createPhoneNode(textNode.ownerDocument, part)
        : textNode.ownerDocument.createTextNode(part.value)
    );
  });

  textNode.parentNode.replaceChild(fragment, textNode);
};

const walkTextNodes = node => {
  if (SKIPPED_TAGS.has(node.nodeName)) return;

  Array.from(node.childNodes).forEach(child => {
    if (child.nodeType === Node.TEXT_NODE) {
      replaceTextNode(child);
      return;
    }

    if (child.nodeType === Node.ELEMENT_NODE) {
      walkTextNodes(child);
    }
  });
};

export const linkifyWhatsmeowPhoneNumbers = html => {
  if (!html || typeof DOMParser === 'undefined') return html;

  const document = new DOMParser().parseFromString(html, 'text/html');
  walkTextNodes(document.body);
  return document.body.innerHTML;
};

export const whatsmeowPhoneElementFromTarget = target =>
  target?.closest?.('[data-whatsmeow-phone-number]');
