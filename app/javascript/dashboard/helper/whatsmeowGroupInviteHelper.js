const GROUP_INVITE_PATTERN =
  /(^|[^\p{L}\p{N}_/])((?:https?:\/\/)?chat\.whatsapp\.com\/(?:invite\/)?[A-Za-z0-9_-]+(?:\?[^\s<]*)?)/giu;

const SKIPPED_TAGS = new Set([
  'A',
  'BUTTON',
  'CODE',
  'PRE',
  'SCRIPT',
  'STYLE',
  'TEXTAREA',
]);

const GROUP_INVITE_TOKEN_CLASS =
  'skip-context-menu cursor-pointer font-semibold text-n-teal-11 underline decoration-n-teal-9/60 underline-offset-2 transition-colors hover:text-n-teal-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/50';

export const whatsmeowGroupInviteCode = value => {
  let rawValue = (value || '').toString().trim();
  if (!rawValue) return '';

  rawValue = rawValue.replace(/^https?:\/\//i, '').replace(/^www\./i, '');

  if (!rawValue.toLowerCase().startsWith('chat.whatsapp.com/')) return '';

  const path = rawValue
    .slice('chat.whatsapp.com/'.length)
    .split(/[?#]/)[0]
    .split('/')
    .filter(Boolean);
  const code = (path[path.length - 1] || '').replace(
    /^[^A-Za-z0-9_-]+|[^A-Za-z0-9_-]+$/g,
    ''
  );

  return /^[A-Za-z0-9_-]{6,}$/.test(code) ? code : '';
};

export const whatsmeowGroupInviteUrl = value => {
  const code = whatsmeowGroupInviteCode(value);
  return code ? `https://chat.whatsapp.com/${code}` : '';
};

export const whatsmeowGroupInviteParts = text => {
  const parts = [];
  const pattern = new RegExp(GROUP_INVITE_PATTERN);
  let lastIndex = 0;
  let match = pattern.exec(text);

  while (match !== null) {
    const boundary = match[1] || '';
    const rawLink = match[2] || '';
    const linkStart = match.index + boundary.length;
    const linkEnd = linkStart + rawLink.length;
    const code = whatsmeowGroupInviteCode(rawLink);

    if (code) {
      if (linkStart > lastIndex) {
        parts.push({ type: 'text', value: text.slice(lastIndex, linkStart) });
      }

      parts.push({
        type: 'group_invite',
        value: rawLink,
        code,
        url: whatsmeowGroupInviteUrl(rawLink),
      });
      lastIndex = linkEnd;
    }

    match = pattern.exec(text);
  }

  if (lastIndex < text.length) {
    parts.push({ type: 'text', value: text.slice(lastIndex) });
  }

  return parts.length ? parts : [{ type: 'text', value: text }];
};

const applyGroupInviteAttributes = (node, { code, url }) => {
  node.setAttribute('data-selection-ignore', 'true');
  node.setAttribute('data-whatsmeow-group-invite-code', code);
  node.setAttribute('data-whatsmeow-group-invite-url', url);
};

const createGroupInviteNode = (document, part) => {
  const node = document.createElement('a');
  node.className = GROUP_INVITE_TOKEN_CLASS;
  node.href = part.url;
  node.textContent = part.value;
  node.setAttribute('role', 'button');
  node.setAttribute('target', '_blank');
  node.setAttribute('rel', 'noreferrer noopener nofollow');
  applyGroupInviteAttributes(node, part);
  return node;
};

const annotateAnchor = anchor => {
  const value = anchor.getAttribute('href') || anchor.textContent || '';
  const code = whatsmeowGroupInviteCode(value);
  if (!code) return;

  const url = whatsmeowGroupInviteUrl(value);
  anchor.className = [anchor.className, 'skip-context-menu']
    .filter(Boolean)
    .join(' ');
  anchor.setAttribute('role', 'button');
  applyGroupInviteAttributes(anchor, { code, url });
};

const replaceTextNode = textNode => {
  const parts = whatsmeowGroupInviteParts(textNode.textContent || '');
  if (!parts.some(part => part.type === 'group_invite')) return;

  const fragment = textNode.ownerDocument.createDocumentFragment();
  parts.forEach(part => {
    fragment.appendChild(
      part.type === 'group_invite'
        ? createGroupInviteNode(textNode.ownerDocument, part)
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

export const linkifyWhatsmeowGroupInvites = html => {
  if (!html || typeof DOMParser === 'undefined') return html;

  const document = new DOMParser().parseFromString(html, 'text/html');
  Array.from(document.body.querySelectorAll('a')).forEach(annotateAnchor);
  walkTextNodes(document.body);
  return document.body.innerHTML;
};

export const whatsmeowGroupInviteElementFromTarget = target =>
  target?.closest?.('[data-whatsmeow-group-invite-code]');
